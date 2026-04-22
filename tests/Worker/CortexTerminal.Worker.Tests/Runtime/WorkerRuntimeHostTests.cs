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
        await gateway.RaiseResizeSessionAsync(new ResizePtyRequest("sess-1", 100, 45));
        await gateway.RaiseCloseSessionAsync(new CloseSessionRequest("sess-1"));

        gateway.StartCallCount.Should().Be(1);
        gateway.RegisteredWorkerIds.Should().Equal("worker-1");
        host.ActiveSessionCount.Should().Be(0);
        process.WrittenPayloads.Should().ContainSingle().Which.Should().Equal([0x01]);
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
}

internal sealed class FakeWorkerGatewayClient : IWorkerGatewayClient
{
    private readonly List<Func<StartSessionCommand, Task>> _startHandlers = [];
    private readonly List<Func<WriteInputFrame, Task>> _writeHandlers = [];
    private readonly List<Func<ResizePtyRequest, Task>> _resizeHandlers = [];
    private readonly List<Func<CloseSessionRequest, Task>> _closeHandlers = [];
    private readonly List<Func<string?, Task>> _reconnectHandlers = [];
    private readonly ConcurrentDictionary<string, TaskCompletionSource<TerminalChunk>> _stdoutWaiters = new();
    private readonly ConcurrentDictionary<string, TaskCompletionSource<TerminalChunk>> _stderrWaiters = new();
    private readonly ConcurrentDictionary<string, TaskCompletionSource<SessionExited>> _exitWaiters = new();

    public List<string> RegisteredWorkerIds { get; } = [];
    public List<TerminalChunk> StdoutChunks { get; } = [];
    public List<TerminalChunk> StderrChunks { get; } = [];
    public List<SessionExited> ExitedEvents { get; } = [];
    public List<SessionStartFailedEvent> StartFailedEvents { get; } = [];
    public int StartCallCount { get; private set; }
    public int DisposeCount { get; private set; }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        StartCallCount++;
        return Task.CompletedTask;
    }

    public Task RegisterAsync(string workerId, CancellationToken cancellationToken)
    {
        RegisteredWorkerIds.Add(workerId);
        return Task.CompletedTask;
    }

    public IDisposable OnStartSession(Func<StartSessionCommand, Task> handler)
        => Register(_startHandlers, handler);

    public IDisposable OnWriteInput(Func<WriteInputFrame, Task> handler)
        => Register(_writeHandlers, handler);

    public IDisposable OnResizeSession(Func<ResizePtyRequest, Task> handler)
        => Register(_resizeHandlers, handler);

    public IDisposable OnCloseSession(Func<CloseSessionRequest, Task> handler)
        => Register(_closeHandlers, handler);

    public IDisposable OnReconnected(Func<string?, Task> handler)
        => Register(_reconnectHandlers, handler);

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
