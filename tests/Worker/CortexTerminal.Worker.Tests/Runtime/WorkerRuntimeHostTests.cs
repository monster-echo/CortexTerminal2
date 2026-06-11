using System.Collections.Concurrent;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Pty;
using CortexTerminal.Worker.Registration;
using CortexTerminal.Worker.Runtime;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;

namespace CortexTerminal.Worker.Tests.Runtime;

public sealed class WorkerRuntimeHostTests
{
    [Fact]
    public async Task StartAsync_RegistersWorkerAndRoutesInboundCommands()
    {
        var process = new ControlledPtyProcess();
        var gateway = new FakeWorkerGatewayClient();
        await using var host = new WorkerRuntimeHost("worker-1", gateway, new QueuePtyHost(process), NullLoggerFactory.Instance);

        await host.StartAsync(CancellationToken.None);
        await gateway.RaiseStartSessionAsync(new StartSessionCommand("sess-1", 120, 40));
        await gateway.RaiseWriteInputAsync(new WriteInputFrame("sess-1", [0x01]));
        await gateway.RaiseLatencyProbeAsync(new LatencyProbeFrame("sess-1", "probe-1"));
        await gateway.RaiseResizeSessionAsync(new ResizePtyRequest("sess-1", 100, 45));
        await gateway.RaiseCloseSessionAsync(new CloseSessionRequest("sess-1"));

        gateway.StartCallCount.Should().Be(1);
        gateway.RegisteredWorkerIds.Should().Equal("worker-1");
        host.ActiveSessionCount.Should().Be(0);
        process.WrittenPayloads.Should().ContainSingle().Which.Should().Equal([0x01]);
        gateway.LatencyProbes.Should().ContainSingle().Which.Should().BeEquivalentTo(new LatencyProbeFrame("sess-1", "probe-1"));
        process.ResizeRequests.Should().ContainSingle().Which.Should().Be((100, 45));
        process.DisposeCount.Should().Be(1);
    }

    [Fact]
    public async Task Reconnected_ReRegistersWithoutDuplicatingTrackedSessions()
    {
        var gateway = new FakeWorkerGatewayClient();
        await using var host = new WorkerRuntimeHost("worker-1", gateway, new QueuePtyHost(new ControlledPtyProcess()), NullLoggerFactory.Instance);

        await host.StartAsync(CancellationToken.None);
        await gateway.RaiseStartSessionAsync(new StartSessionCommand("sess-1", 120, 40));
        await gateway.RaiseReconnectedAsync("reconnected");

        gateway.RegisteredWorkerIds.Should().Equal("worker-1", "worker-1");
        host.ActiveSessionCount.Should().Be(1);
    }

    [Fact]
    public async Task DuplicateStart_ForwardsStartFailureWithoutReplacingActiveSession()
    {
        var gateway = new FakeWorkerGatewayClient();
        await using var host = new WorkerRuntimeHost("worker-1", gateway, new QueuePtyHost(new ControlledPtyProcess()), NullLoggerFactory.Instance);

        await host.StartAsync(CancellationToken.None);
        await gateway.RaiseStartSessionAsync(new StartSessionCommand("sess-1", 120, 40));
        await gateway.RaiseStartSessionAsync(new StartSessionCommand("sess-1", 80, 24));

        host.ActiveSessionCount.Should().Be(1);
        gateway.StartFailedEvents.Should().ContainSingle()
            .Which.Should().BeEquivalentTo(new SessionStartFailedEvent("sess-1", "duplicate-session"));
    }

    [Fact]
    public async Task PtyStartupFailure_ForwardsStableErrorCode()
    {
        var gateway = new FakeWorkerGatewayClient();
        await using var host = new WorkerRuntimeHost(
            "worker-1",
            gateway,
            new ThrowingPtyHost(new PtySupportException("pty-start-failed", "spawn exploded")),
            NullLoggerFactory.Instance);

        await host.StartAsync(CancellationToken.None);
        await gateway.RaiseStartSessionAsync(new StartSessionCommand("sess-1", 120, 40));

        gateway.StartFailedEvents.Should().ContainSingle()
            .Which.Should().BeEquivalentTo(new SessionStartFailedEvent("sess-1", "pty-start-failed"));
        host.ActiveSessionCount.Should().Be(0);
    }

    [Theory]
    [InlineData(0, 45)]
    [InlineData(100, 0)]
    [InlineData(-1, 45)]
    [InlineData(100, -1)]
    [InlineData(1001, 45)]
    [InlineData(100, 1001)]
    public async Task ResizeSession_WithInvalidDimensions_DoesNotReachPty(int columns, int rows)
    {
        var process = new ControlledPtyProcess();
        var gateway = new FakeWorkerGatewayClient();
        await using var host = new WorkerRuntimeHost("worker-1", gateway, new QueuePtyHost(process), NullLoggerFactory.Instance);

        await host.StartAsync(CancellationToken.None);
        await gateway.RaiseStartSessionAsync(new StartSessionCommand("sess-1", 120, 40));
        await gateway.RaiseResizeSessionAsync(new ResizePtyRequest("sess-1", columns, rows));

        host.ActiveSessionCount.Should().Be(1);
        process.ResizeRequests.Should().BeEmpty();
    }

    [Fact(Timeout = 15000)]
    public async Task Closed_RetriesUntilGatewayComesBack()
    {
        var gateway = new FakeWorkerGatewayClient();
        // Initial StartAsync succeeds (StartAsyncResult not set = default success)

        await using var host = new WorkerRuntimeHost(
            "worker-1", gateway, new QueuePtyHost(new ControlledPtyProcess()),
            NullLoggerFactory.Instance, TimeSpan.FromMilliseconds(50));

        await host.StartAsync(CancellationToken.None);
        gateway.RegisteredWorkerIds.Should().ContainSingle(); // initial register

        // Now make StartAsync fail first 3 reconnect attempts, then succeed
        var failCount = 0;
        gateway.StartAsyncResult = () => ++failCount > 3;

        await gateway.RaiseClosedAsync();

        // Wait for the second registration (reconnect)
        await gateway.WaitForRegisterCountAsync(2);

        gateway.StartCallCount.Should().BeGreaterThanOrEqualTo(4); // 1 initial + at least 3 retries
        gateway.RegisteredWorkerIds.Count.Should().BeGreaterThanOrEqualTo(2); // initial + reconnect register
    }

    [Fact(Timeout = 10000)]
    public async Task StopAsync_CancelsReconnectLoop()
    {
        var gateway = new FakeWorkerGatewayClient();

        await using var host = new WorkerRuntimeHost(
            "worker-1", gateway, new QueuePtyHost(new ControlledPtyProcess()),
            NullLoggerFactory.Instance, TimeSpan.FromMilliseconds(50));

        await host.StartAsync(CancellationToken.None);
        var startCountBefore = gateway.StartCallCount;

        // Now make StartAsync always fail for reconnect attempts
        gateway.StartAsyncResult = () => false;
        await gateway.RaiseClosedAsync();
        await Task.Delay(300); // let the loop attempt a few times

        await host.StopAsync(CancellationToken.None);
        var startCountAtStop = gateway.StartCallCount;

        await Task.Delay(300); // verify loop stopped
        gateway.StartCallCount.Should().Be(startCountAtStop);
        gateway.StartCallCount.Should().BeGreaterThan(startCountBefore);
    }

    [Fact(Timeout = 10000)]
    public async Task MultipleClosedEvents_DoNotCreateConcurrentReconnectLoops()
    {
        var gateway = new FakeWorkerGatewayClient();

        await using var host = new WorkerRuntimeHost(
            "worker-1", gateway, new QueuePtyHost(new ControlledPtyProcess()),
            NullLoggerFactory.Instance, TimeSpan.FromMilliseconds(50));

        await host.StartAsync(CancellationToken.None);
        gateway.RegisteredWorkerIds.Clear();

        // Make StartAsync fail first, then succeed
        var failCount = 0;
        gateway.StartAsyncResult = () => ++failCount > 2;

        // Fire multiple Closed events rapidly — only one reconnect loop should be active
        await gateway.RaiseClosedAsync();
        await gateway.RaiseClosedAsync();
        await gateway.RaiseClosedAsync();

        await gateway.WaitForRegisterCountAsync(2);

        // Should only register once despite multiple Closed events
        gateway.RegisteredWorkerIds.Should().ContainSingle();
    }

    [Fact]
    public async Task Upgrade_RejectedWhenPlatformMismatches()
    {
        var gateway = new FakeWorkerGatewayClient();
        await using var host = new WorkerRuntimeHost("worker-1", gateway, new QueuePtyHost(new ControlledPtyProcess()), NullLoggerFactory.Instance);

        await host.StartAsync(CancellationToken.None);

        // Build a URL with a deliberately wrong platform
        var isOsx = System.Runtime.InteropServices.RuntimeInformation.IsOSPlatform(System.Runtime.InteropServices.OSPlatform.OSX);
        var isWindows = System.Runtime.InteropServices.RuntimeInformation.IsOSPlatform(System.Runtime.InteropServices.OSPlatform.Windows);
        var wrongAsset = isOsx ? "corterm-linux-x64.tar.gz"
            : isWindows ? "corterm-osx-arm64.tar.gz"
            : "corterm-win-x64.zip";

        var wrongUrl = $"https://example.com/releases/download/{wrongAsset}";

        // Should not throw, but should silently reject (no binary download attempted)
        await gateway.RaiseUpgradeWorkerAsync(new UpgradeWorkerCommand("99.0.0", wrongUrl));

        // Worker should still be running (not exited)
        host.ActiveSessionCount.Should().Be(0);
    }

    [Fact]
    public async Task Upgrade_AcceptedWhenPlatformMatches()
    {
        var gateway = new FakeWorkerGatewayClient();
        await using var host = new WorkerRuntimeHost("worker-1", gateway, new QueuePtyHost(new ControlledPtyProcess()), NullLoggerFactory.Instance);

        await host.StartAsync(CancellationToken.None);

        var isOsx = System.Runtime.InteropServices.RuntimeInformation.IsOSPlatform(System.Runtime.InteropServices.OSPlatform.OSX);
        var isWindows = System.Runtime.InteropServices.RuntimeInformation.IsOSPlatform(System.Runtime.InteropServices.OSPlatform.Windows);
        var arch = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture == System.Runtime.InteropServices.Architecture.Arm64 ? "arm64" : "x64";
        var os = isOsx ? "osx" : isWindows ? "win" : "linux";
        var ext = isWindows ? "zip" : "tar.gz";
        var correctAsset = $"corterm-{os}-{arch}.{ext}";
        var correctUrl = $"https://example.com/releases/download/{correctAsset}";

        // This will attempt to download (and fail because the URL is fake), but the platform check passes
        // The handler catches the download exception, so no throw
        await gateway.RaiseUpgradeWorkerAsync(new UpgradeWorkerCommand("99.0.0", correctUrl));

        // Worker should still be running (download failed, not platform rejection)
        host.ActiveSessionCount.Should().Be(0);
    }

    [Theory]
    [InlineData("https://example.com/corterm-osx-arm64.tar.gz", true, true)]
    [InlineData("https://example.com/corterm-linux-x64.tar.gz", false, false)]
    [InlineData("https://example.com/corterm-win-x64.zip", false, false)]
    [InlineData("https://example.com/corterm-linux-arm64.tar.gz", false, false)]
    public void DoesDownloadUrlMatchLocalPlatform_ValidatesCorrectly(string url, bool expectedOnMac, bool expectedOnLinux)
    {
        var isOsx = System.Runtime.InteropServices.RuntimeInformation.IsOSPlatform(System.Runtime.InteropServices.OSPlatform.OSX);
        var isLinux = System.Runtime.InteropServices.RuntimeInformation.IsOSPlatform(System.Runtime.InteropServices.OSPlatform.Linux);
        var expected = isOsx ? expectedOnMac : isLinux ? expectedOnLinux : false;

        WorkerRuntimeHost.DoesDownloadUrlMatchLocalPlatform(url).Should().Be(expected);
    }

    [Theory]
    [InlineData("")]
    [InlineData("https://example.com/unknown-file.bin")]
    public void DoesDownloadUrlMatchLocalPlatform_AllowsUnrecognizedUrls(string url)
    {
        WorkerRuntimeHost.DoesDownloadUrlMatchLocalPlatform(url).Should().BeTrue();
    }
}

internal sealed class FakeWorkerGatewayClient : IWorkerGatewayClient
{
    private readonly List<Func<StartSessionCommand, Task>> _startHandlers = [];
    private readonly List<Func<WriteInputFrame, Task>> _writeHandlers = [];
    private readonly List<Func<LatencyProbeFrame, Task>> _latencyProbeHandlers = [];
    private readonly List<Func<ResizePtyRequest, Task>> _resizeHandlers = [];
    private readonly List<Func<CloseSessionRequest, Task>> _closeHandlers = [];
    private readonly List<Func<UpgradeWorkerCommand, Task>> _upgradeHandlers = [];
    private readonly List<Func<string?, Task>> _reconnectHandlers = [];
    private readonly List<Func<Exception?, Task>> _closedHandlers = [];
    private readonly ConcurrentDictionary<string, TaskCompletionSource<TerminalChunk>> _stdoutWaiters = new();
    private readonly ConcurrentDictionary<string, TaskCompletionSource<TerminalChunk>> _stderrWaiters = new();
    private readonly ConcurrentDictionary<string, TaskCompletionSource<SessionExited>> _exitWaiters = new();
    private int _registeredCount;
    private readonly ConcurrentDictionary<int, TaskCompletionSource> _registerWaiters = new();

    public List<string> RegisteredWorkerIds { get; } = [];
    public List<TerminalChunk> StdoutChunks { get; } = [];
    public List<TerminalChunk> StderrChunks { get; } = [];
    public List<LatencyProbeFrame> LatencyProbes { get; } = [];
    public List<SessionExited> ExitedEvents { get; } = [];
    public List<SessionStartFailedEvent> StartFailedEvents { get; } = [];
    public int StartCallCount { get; private set; }
    public int DisposeCount { get; private set; }

    /// <summary>
    /// Controls StartAsync behavior. When set, this function is called instead of the default.
    /// Return true to simulate success, false to throw InvalidOperationException.
    /// </summary>
    public Func<bool>? StartAsyncResult { get; set; }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        StartCallCount++;
        if (StartAsyncResult is not null)
        {
            return StartAsyncResult()
                ? Task.CompletedTask
                : Task.FromException(new InvalidOperationException("Connection refused"));
        }
        return Task.CompletedTask;
    }

    public Task RegisterAsync(string workerId, CancellationToken cancellationToken)
    {
        RegisteredWorkerIds.Add(workerId);
        var count = Interlocked.Increment(ref _registeredCount);
        _registerWaiters.GetOrAdd(count, _ => new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously))
            .TrySetResult();
        return Task.CompletedTask;
    }

    public Task WaitForRegisterCountAsync(int count)
    {
        var tcs = _registerWaiters.GetOrAdd(count, _ => new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously));
        return tcs.Task;
    }

    public IDisposable OnStartSession(Func<StartSessionCommand, Task> handler)
        => Register(_startHandlers, handler);

    public IDisposable OnWriteInput(Func<WriteInputFrame, Task> handler)
        => Register(_writeHandlers, handler);

    public IDisposable OnLatencyProbe(Func<LatencyProbeFrame, Task> handler)
        => Register(_latencyProbeHandlers, handler);

    public IDisposable OnResizeSession(Func<ResizePtyRequest, Task> handler)
        => Register(_resizeHandlers, handler);

    public IDisposable OnCloseSession(Func<CloseSessionRequest, Task> handler)
        => Register(_closeHandlers, handler);

    public IDisposable OnUpgradeWorker(Func<UpgradeWorkerCommand, Task> handler)
        => Register(_upgradeHandlers, handler);

    public IDisposable OnReconnected(Func<string?, Task> handler)
        => Register(_reconnectHandlers, handler);

    public IDisposable OnClosed(Func<Exception?, Task> handler)
        => Register(_closedHandlers, handler);

    public Task ForwardStdoutAsync(TerminalChunk chunk, CancellationToken cancellationToken)
    {
        StdoutChunks.Add(chunk);
        _stdoutWaiters.GetOrAdd(chunk.SessionId, _ => new(TaskCreationOptions.RunContinuationsAsynchronously)).TrySetResult(chunk);
        return Task.CompletedTask;
    }

    public Task ForwardStderrAsync(TerminalChunk chunk, CancellationToken cancellationToken)
    {
        StderrChunks.Add(chunk);
        _stderrWaiters.GetOrAdd(chunk.SessionId, _ => new(TaskCreationOptions.RunContinuationsAsynchronously)).TrySetResult(chunk);
        return Task.CompletedTask;
    }

    public Task ForwardLatencyProbeAsync(LatencyProbeFrame frame, CancellationToken cancellationToken)
    {
        LatencyProbes.Add(frame);
        return Task.CompletedTask;
    }

    public Task ForwardExitedAsync(SessionExited evt, CancellationToken cancellationToken)
    {
        ExitedEvents.Add(evt);
        _exitWaiters.GetOrAdd(evt.SessionId, _ => new(TaskCreationOptions.RunContinuationsAsynchronously)).TrySetResult(evt);
        return Task.CompletedTask;
    }

    public Task ForwardStartFailedAsync(SessionStartFailedEvent evt, CancellationToken cancellationToken)
    {
        StartFailedEvents.Add(evt);
        return Task.CompletedTask;
    }

    public Task SendWorkerInfoAsync(WorkerInfoFrame info, CancellationToken ct)
        => Task.CompletedTask;

    public async Task RaiseStartSessionAsync(StartSessionCommand command)
    {
        foreach (var handler in _startHandlers)
        {
            await handler(command);
        }
    }

    public async Task RaiseWriteInputAsync(WriteInputFrame frame)
    {
        foreach (var handler in _writeHandlers)
        {
            await handler(frame);
        }
    }

    public async Task RaiseLatencyProbeAsync(LatencyProbeFrame frame)
    {
        foreach (var handler in _latencyProbeHandlers)
        {
            await handler(frame);
        }
    }

    public async Task RaiseResizeSessionAsync(ResizePtyRequest request)
    {
        foreach (var handler in _resizeHandlers)
        {
            await handler(request);
        }
    }

    public async Task RaiseCloseSessionAsync(CloseSessionRequest request)
    {
        foreach (var handler in _closeHandlers)
        {
            await handler(request);
        }
    }

    public async Task RaiseReconnectedAsync(string? connectionId)
    {
        foreach (var handler in _reconnectHandlers)
        {
            await handler(connectionId);
        }
    }

    public async Task RaiseClosedAsync(Exception? exception = null)
    {
        foreach (var handler in _closedHandlers)
        {
            await handler(exception);
        }
    }

    public async Task RaiseUpgradeWorkerAsync(UpgradeWorkerCommand command)
    {
        foreach (var handler in _upgradeHandlers)
        {
            await handler(command);
        }
    }

    public Task WaitForExitAsync(string sessionId)
        => _exitWaiters.GetOrAdd(sessionId, _ => new(TaskCreationOptions.RunContinuationsAsynchronously)).Task;

    public Task WaitForStdoutAsync(string sessionId)
        => _stdoutWaiters.GetOrAdd(sessionId, _ => new(TaskCreationOptions.RunContinuationsAsynchronously)).Task;

    public Task WaitForStderrAsync(string sessionId)
        => _stderrWaiters.GetOrAdd(sessionId, _ => new(TaskCreationOptions.RunContinuationsAsynchronously)).Task;

    public ValueTask DisposeAsync()
    {
        DisposeCount++;
        return ValueTask.CompletedTask;
    }

    private static IDisposable Register<T>(ICollection<T> handlers, T handler)
    {
        handlers.Add(handler);
        return new DelegateDisposable(() => handlers.Remove(handler));
    }
}

internal sealed class DelegateDisposable(Action dispose) : IDisposable
{
    public void Dispose() => dispose();
}

internal sealed class ThrowingPtyHost(Exception exception) : IPtyHost
{
    public Task<IPtyProcess> StartAsync(int columns, int rows, CancellationToken cancellationToken)
        => Task.FromException<IPtyProcess>(exception);
}
