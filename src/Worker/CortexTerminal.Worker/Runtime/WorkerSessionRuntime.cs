using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Pty;
using CortexTerminal.Worker.Registration;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Runtime;

public sealed class WorkerSessionRuntime : IAsyncDisposable
{
    private readonly PtySession _session;
    private readonly CancellationTokenSource _lifetime = new();
    private readonly ILogger<WorkerSessionRuntime> _logger;
    private IPtyProcess? _process;
    private Task? _stdoutPump;
    private Task? _stderrPump;
    private int _disposed;
    private int _terminated;

    public WorkerSessionRuntime(
        string sessionId,
        IPtyHost ptyHost,
        IWorkerGatewayClient gatewayClient,
        ILogger<WorkerSessionRuntime> logger)
    {
        SessionId = sessionId;
        GatewayClient = gatewayClient;
        _logger = logger;
        _session = new PtySession(ptyHost, new ScrollbackBuffer(64 * 1024));
    }

    public string SessionId { get; }
    public IWorkerGatewayClient GatewayClient { get; }
    public event Func<string, Task>? Terminated;

    public async Task StartAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        _process = await _session.StartAsync(SessionId, columns, rows, cancellationToken);
        _stdoutPump = PumpAsync(_session.ReadStdoutChunksAsync(SessionId, _lifetime.Token), GatewayClient.ForwardStdoutAsync);
        _stderrPump = PumpAsync(_session.ReadStderrChunksAsync(SessionId, _lifetime.Token), GatewayClient.ForwardStderrAsync);
        _ = ObserveExitAsync(_process);
    }

    public Task WriteInputAsync(byte[] payload, CancellationToken cancellationToken)
        => _process is null
            ? Task.CompletedTask
            : _process.WriteAsync(payload, cancellationToken);

    public Task ResizeAsync(int columns, int rows, CancellationToken cancellationToken)
        => _process is null
            ? Task.CompletedTask
            : _process.ResizeAsync(columns, rows, cancellationToken);

    public async Task CloseAsync(CancellationToken cancellationToken)
    {
        await DisposeProcessAsync();
        await NotifyTerminatedAsync();
    }

    public async ValueTask DisposeAsync()
    {
        await CloseAsync(CancellationToken.None);
        _lifetime.Dispose();
    }

    private async Task PumpAsync(
        IAsyncEnumerable<TerminalChunk> chunks,
        Func<TerminalChunk, CancellationToken, Task> forward)
    {
        try
        {
            await foreach (var chunk in chunks)
            {
                await forward(chunk, CancellationToken.None);
            }
        }
        catch (OperationCanceledException) when (_lifetime.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            _logger.LogError(exception, "Failed while pumping terminal output for session {SessionId}.", SessionId);
        }
    }

    private async Task ObserveExitAsync(IPtyProcess process)
    {
        try
        {
            var exitCode = await process.WaitForExitAsync(_lifetime.Token);
            await GatewayClient.ForwardExitedAsync(
                new SessionExited(SessionId, exitCode, "process-exited"),
                CancellationToken.None);
        }
        catch (OperationCanceledException) when (_lifetime.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            _logger.LogError(exception, "Failed while waiting for session {SessionId} to exit.", SessionId);
        }
        finally
        {
            await AwaitPumpTasksAsync();
            await DisposeProcessAsync();
            await NotifyTerminatedAsync();
        }
    }

    private Task AwaitPumpTasksAsync()
        => Task.WhenAll(_stdoutPump ?? Task.CompletedTask, _stderrPump ?? Task.CompletedTask);

    private async Task DisposeProcessAsync()
    {
        if (Interlocked.Exchange(ref _disposed, 1) == 1)
        {
            return;
        }

        _lifetime.Cancel();

        if (_process is not null)
        {
            await _process.DisposeAsync();
        }
    }

    private async Task NotifyTerminatedAsync()
    {
        if (Interlocked.Exchange(ref _terminated, 1) == 1)
        {
            return;
        }

        if (Terminated is null)
        {
            return;
        }

        foreach (var handler in Terminated.GetInvocationList().Cast<Func<string, Task>>())
        {
            try
            {
                await handler(SessionId);
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Terminated callback failed for session {SessionId}.", SessionId);
            }
        }
    }
}
