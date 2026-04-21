using System.Collections.Concurrent;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Pty;
using CortexTerminal.Worker.Registration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Runtime;

public sealed class WorkerRuntimeHost : IHostedService, IAsyncDisposable
{
    private readonly string _workerId;
    private readonly IWorkerGatewayClient _gatewayClient;
    private readonly IPtyHost _ptyHost;
    private readonly ILogger<WorkerRuntimeHost> _logger;
    private readonly ILoggerFactory _loggerFactory;
    private readonly ConcurrentDictionary<string, WorkerSessionRuntime> _sessions = [];
    private readonly List<IDisposable> _subscriptions = [];

    public WorkerRuntimeHost(
        string workerId,
        IWorkerGatewayClient gatewayClient,
        IPtyHost ptyHost,
        ILoggerFactory loggerFactory)
    {
        _workerId = workerId;
        _gatewayClient = gatewayClient;
        _ptyHost = ptyHost;
        _loggerFactory = loggerFactory;
        _logger = loggerFactory.CreateLogger<WorkerRuntimeHost>();
    }

    public int ActiveSessionCount => _sessions.Count;

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        _subscriptions.Add(_gatewayClient.OnStartSession(HandleStartSessionAsync));
        _subscriptions.Add(_gatewayClient.OnWriteInput(HandleWriteInputAsync));
        _subscriptions.Add(_gatewayClient.OnResizeSession(HandleResizeSessionAsync));
        _subscriptions.Add(_gatewayClient.OnCloseSession(HandleCloseSessionAsync));
        _subscriptions.Add(_gatewayClient.OnReconnected(_ => RegisterWorkerAsync(CancellationToken.None)));

        await _gatewayClient.StartAsync(cancellationToken);
        await RegisterWorkerAsync(cancellationToken);
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        foreach (var subscription in _subscriptions)
        {
            subscription.Dispose();
        }

        _subscriptions.Clear();

        foreach (var session in _sessions.ToArray())
        {
            if (_sessions.TryRemove(session.Key, out var runtime))
            {
                await runtime.CloseAsync(cancellationToken);
                await runtime.DisposeAsync();
            }
        }
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync(CancellationToken.None);
        await _gatewayClient.DisposeAsync();
    }

    private Task RegisterWorkerAsync(CancellationToken cancellationToken)
        => _gatewayClient.RegisterAsync(_workerId, cancellationToken);

    private async Task HandleStartSessionAsync(StartSessionCommand command)
    {
        if (_sessions.ContainsKey(command.SessionId))
        {
            await _gatewayClient.ForwardStartFailedAsync(
                new SessionStartFailedEvent(command.SessionId, "duplicate-session"),
                CancellationToken.None);
            return;
        }

        var runtime = new WorkerSessionRuntime(
            command.SessionId,
            _ptyHost,
            _gatewayClient,
            _loggerFactory.CreateLogger<WorkerSessionRuntime>());

        runtime.Terminated += RemoveSessionAsync;

        if (!_sessions.TryAdd(command.SessionId, runtime))
        {
            await runtime.CloseAsync(CancellationToken.None);
            await runtime.DisposeAsync();
            await _gatewayClient.ForwardStartFailedAsync(
                new SessionStartFailedEvent(command.SessionId, "duplicate-session"),
                CancellationToken.None);
            return;
        }

        try
        {
            await runtime.StartAsync(command.Columns, command.Rows, CancellationToken.None);
        }
        catch (Exception exception)
        {
            _sessions.TryRemove(command.SessionId, out _);
            await runtime.CloseAsync(CancellationToken.None);
            await runtime.DisposeAsync();
            _logger.LogError(exception, "Failed to start session {SessionId}.", command.SessionId);
            await _gatewayClient.ForwardStartFailedAsync(
                new SessionStartFailedEvent(command.SessionId, exception.Message),
                CancellationToken.None);
        }
    }

    private Task HandleWriteInputAsync(WriteInputFrame frame)
        => _sessions.TryGetValue(frame.SessionId, out var runtime)
            ? runtime.WriteInputAsync(frame.Payload, CancellationToken.None)
            : LogMissingSessionAsync(frame.SessionId, "write");

    private Task HandleResizeSessionAsync(ResizePtyRequest request)
        => _sessions.TryGetValue(request.SessionId, out var runtime)
            ? runtime.ResizeAsync(request.Columns, request.Rows, CancellationToken.None)
            : LogMissingSessionAsync(request.SessionId, "resize");

    private async Task HandleCloseSessionAsync(CloseSessionRequest request)
    {
        if (_sessions.TryRemove(request.SessionId, out var runtime))
        {
            await runtime.CloseAsync(CancellationToken.None);
            await runtime.DisposeAsync();
            return;
        }

        await LogMissingSessionAsync(request.SessionId, "close");
    }

    private Task RemoveSessionAsync(string sessionId)
    {
        _sessions.TryRemove(sessionId, out _);
        return Task.CompletedTask;
    }

    private Task LogMissingSessionAsync(string sessionId, string operation)
    {
        _logger.LogInformation("Ignoring {Operation} for unknown session {SessionId}.", operation, sessionId);
        return Task.CompletedTask;
    }
}
