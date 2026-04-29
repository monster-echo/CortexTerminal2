using System.Collections.Concurrent;
using System.Reflection;
using System.Runtime.InteropServices;
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
        _subscriptions.Add(_gatewayClient.OnLatencyProbe(HandleLatencyProbeAsync));
        _subscriptions.Add(_gatewayClient.OnResizeSession(HandleResizeSessionAsync));
        _subscriptions.Add(_gatewayClient.OnCloseSession(HandleCloseSessionAsync));
        _subscriptions.Add(_gatewayClient.OnReconnected(_ => RegisterWorkerAsync(CancellationToken.None)));

        _logger.LogInformation("Worker {WorkerId} is starting.", _workerId);
        await _gatewayClient.StartAsync(cancellationToken);
        await RegisterWorkerAsync(cancellationToken);
        _logger.LogInformation("Worker {WorkerId} has started.", _workerId);
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Worker {WorkerId} is stopping.", _workerId);
        foreach (var subscription in _subscriptions)
        {
            subscription.Dispose();
        }

        _subscriptions.Clear();

        _logger.LogInformation("Closing {SessionCount} active sessions for worker {WorkerId}.", _sessions.Count, _workerId);
        foreach (var session in _sessions.ToArray())
        {
            if (_sessions.TryRemove(session.Key, out var runtime))
            {
                await runtime.CloseAsync(cancellationToken);
                await runtime.DisposeAsync();
            }
        }
        _logger.LogInformation("Worker {WorkerId} has stopped.", _workerId);
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync(CancellationToken.None);
        await _gatewayClient.DisposeAsync();
        _logger.LogInformation("Worker {WorkerId} has been disposed.", _workerId);
    }

    private async Task RegisterWorkerAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Registering worker {WorkerId}.", _workerId);
        await _gatewayClient.RegisterAsync(_workerId, cancellationToken);

        var info = new WorkerInfoFrame(
            _workerId,
            Environment.MachineName,
            RuntimeInformation.OSDescription,
            RuntimeInformation.OSArchitecture.ToString(),
            Environment.MachineName,
            Assembly.GetEntryAssembly()?.GetName().Version?.ToString());

        try
        {
            await _gatewayClient.SendWorkerInfoAsync(info, cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to send worker info for {WorkerId}.", _workerId);
        }
    }

    private async Task HandleStartSessionAsync(StartSessionCommand command)
    {
        if (_sessions.ContainsKey(command.SessionId))
        {
            await _gatewayClient.ForwardStartFailedAsync(
                new SessionStartFailedEvent(command.SessionId, "duplicate-session"),
                CancellationToken.None);
            _logger.LogWarning("Received start command for duplicate session {SessionId}.", command.SessionId);
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
            _logger.LogInformation("Starting session {SessionId}.", command.SessionId);
            await runtime.StartAsync(command.Columns, command.Rows, CancellationToken.None);
        }
        catch (Exception exception)
        {
            _sessions.TryRemove(command.SessionId, out _);
            await runtime.CloseAsync(CancellationToken.None);
            await runtime.DisposeAsync();
            _logger.LogError(exception, "Failed to start session {SessionId}.", command.SessionId);
            var reason = exception is PtySupportException ptySupportException
                ? ptySupportException.ErrorCode
                : exception.Message;
            await _gatewayClient.ForwardStartFailedAsync(
                new SessionStartFailedEvent(command.SessionId, reason),
                CancellationToken.None);
        }
    }

    private Task HandleWriteInputAsync(WriteInputFrame frame)
    {
        var payload = frame.Payload.ToArray();
        _logger.LogInformation("Received input for session {SessionId}: {Payload}", frame.SessionId, BitConverter.ToString(payload));

        return _sessions.TryGetValue(frame.SessionId, out var runtime)
        ? runtime.WriteInputAsync(frame.Payload, CancellationToken.None)
        : LogMissingSessionAsync(frame.SessionId, "write");
    }

    private Task HandleLatencyProbeAsync(LatencyProbeFrame frame)
    {
        _logger.LogDebug("Received latency probe for session {SessionId}: {ProbeId}", frame.SessionId, frame.ProbeId);

        return _sessions.ContainsKey(frame.SessionId)
            ? _gatewayClient.ForwardLatencyProbeAsync(frame, CancellationToken.None)
            : LogMissingSessionAsync(frame.SessionId, "latency-probe");
    }

    private Task HandleResizeSessionAsync(ResizePtyRequest request)
    {
        _logger.LogInformation("Received resize for session {SessionId}: {Columns}x{Rows}", request.SessionId, request.Columns, request.Rows);
        return _sessions.TryGetValue(request.SessionId, out var runtime)
        ? runtime.ResizeAsync(request.Columns, request.Rows, CancellationToken.None)
        : LogMissingSessionAsync(request.SessionId, "resize");
    }

    private async Task HandleCloseSessionAsync(CloseSessionRequest request)
    {
        _logger.LogInformation("Received close for session {SessionId}", request.SessionId);
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
        _logger.LogInformation("Removing session {SessionId}", sessionId);

        _sessions.TryRemove(sessionId, out _);
        return Task.CompletedTask;
    }

    private Task LogMissingSessionAsync(string sessionId, string operation)
    {
        _logger.LogInformation("Ignoring {Operation} for unknown session {SessionId}.", operation, sessionId);
        return Task.CompletedTask;
    }
}
