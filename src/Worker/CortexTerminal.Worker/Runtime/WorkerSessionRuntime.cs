using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Agent;
using CortexTerminal.Worker.Pty;
using CortexTerminal.Worker.Registration;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Runtime;

public sealed class WorkerSessionRuntime : IAsyncDisposable
{
    private readonly PtySession _session;
    private readonly CancellationTokenSource _lifetime = new();
    private readonly ILogger<WorkerSessionRuntime> _logger;
    private readonly IAgentIntegration? _agentIntegration;
    private IPtyProcess? _process;
    private Task? _stdoutPump;
    private Task? _stderrPump;
    private int _disposed;
    private int _terminated;

    public WorkerSessionRuntime(
        string sessionId,
        IPtyHost ptyHost,
        IWorkerGatewayClient gatewayClient,
        ILogger<WorkerSessionRuntime> logger,
        int maxBytes,
        IAgentIntegration? agentIntegration = null)
    {
        SessionId = sessionId;
        GatewayClient = gatewayClient;
        _logger = logger;
        _session = new PtySession(ptyHost, new ScrollbackBuffer(maxBytes));
        _agentIntegration = agentIntegration;
    }

    private long _outputBytes;
    public DateTimeOffset StartedAtUtc { get; } = DateTimeOffset.UtcNow;
    public string? Directory { get; private set; }
    public bool HasOutput => Interlocked.Read(ref _outputBytes) > 0;
    public string SessionId { get; }
    public IWorkerGatewayClient GatewayClient { get; }
    public event Func<string, Task>? Terminated;

    public async Task StartAsync(int columns, int rows, string? cwd, CancellationToken cancellationToken)
    {
        Directory = string.IsNullOrEmpty(cwd) ? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) : cwd;
        var env = new Dictionary<string, string>();
        // Claude Code hooks are merged into ~/.claude/settings.json (non-invasive, no PATH
        // shims). The reporter script exec'd by those hooks is a subprocess of claude, so it
        // inherits these per-session env vars: the loopback endpoint URL (random port per
        // worker start) and the Corterm session id that fronts the envelope.
        if (_agentIntegration is { Enabled: true })
        {
            env["CORTERM_SESSION_ID"] = SessionId;
            env["CORTERM_AGENT_HOOK_URL"] = _agentIntegration.HookUrl;
        }
        _process = await _session.StartAsync(SessionId, columns, rows, cwd, env, cancellationToken);
        _logger.LogDebug("Session {SessionId} PTY started ({Columns}x{Rows}).", SessionId, columns, rows);
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

    public IReadOnlyList<TerminalChunk> GetScrollback() => _session.GetScrollback();

    /// <summary>Incremental scrollback after the client's cursor; see ScrollbackBuffer.CreateDelta.</summary>
    public ScrollbackDelta GetScrollbackSince(long sinceSeq) => _session.GetScrollbackSince(sinceSeq);

    public async Task CloseAsync(CancellationToken cancellationToken)
    {
        await DisposeProcessAsync();
        await GatewayClient.ForwardExitedAsync(
            new SessionExited(SessionId, 0, "closed-by-request"),
            CancellationToken.None);
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
                Interlocked.Add(ref _outputBytes, chunk.Payload.Length);
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
            _logger.LogInformation("Session {SessionId} process exited with code {ExitCode}.", SessionId, exitCode);
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
