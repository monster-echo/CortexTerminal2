using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Audit;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Stats;
using CortexTerminal.Gateway.Tests.Workers;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Hubs;

public sealed class TerminalHubReconnectTests
{
    [Fact]
    public async Task ReattachSession_SendsReattachedReplayAndCompletionInOrder()
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = TestSessionFactory.CreateCoordinator(workers);
        var replayCoordinator = new ReplayCoordinator();
        var dispatcher = new ScrollbackWorkerCommandDispatcher(
            new TerminalChunk("dummy", "stdout", [0x01, 0x02]),
            new TerminalChunk("dummy", "stderr", [0x03]));
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var detachedAtUtc = new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero);

        await sessions.DetachSessionAsync("user-1", sessionId, detachedAtUtc, CancellationToken.None);

        var caller = new RecordingClientProxy();
        var hub = CreateTerminalHub(sessions, replayCoordinator, dispatcher, new FixedTimeProvider(detachedAtUtc.AddMinutes(4)));
        hub.Context = new TestHubCallerContext("client-reattached", "user-1");
        hub.Clients = new TestHubCallerClients(caller);

        var result = await InvokeAsync<ReattachSessionResult>(
            hub,
            "ReattachSession",
            new ReattachSessionRequest(sessionId));

        result.Should().BeEquivalentTo(ReattachSessionResult.Success());
        caller.Invocations.Select(static invocation => invocation.Method).Should().Equal(
            "SessionReattached",
            "ReplayChunk",
            "ReplayChunk",
            "ReplayCompleted");
        caller.Invocations[0].Arguments[0].Should().BeEquivalentTo(new SessionReattachedEvent(sessionId));
        caller.Invocations[1].Arguments[0].Should().BeEquivalentTo(new ReplayChunk(sessionId, "stdout", [0x01, 0x02]));
        caller.Invocations[2].Arguments[0].Should().BeEquivalentTo(new ReplayChunk(sessionId, "stderr", [0x03]));
        caller.Invocations[3].Arguments[0].Should().BeEquivalentTo(new ReplayCompleted(sessionId));
    }

    [Fact]
    public async Task ReattachSession_ResumesLiveFanOutOnlyAfterReplayCompletes()
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = TestSessionFactory.CreateCoordinator(workers);
        var replayCoordinator = new ReplayCoordinator();
        var dispatcher = new ScrollbackWorkerCommandDispatcher(
            new TerminalChunk("dummy", "stdout", [0xAA]));
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var detachedAtUtc = new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero);

        await sessions.DetachSessionAsync("user-1", sessionId, detachedAtUtc, CancellationToken.None);

        Task? liveForwardTask = null;
        var liveChunk = new TerminalChunk(sessionId, "stdout", [0xBB]);
        WorkerHub? workerHub = null;
        var caller = new RecordingClientProxy((method, _) =>
        {
            if (method == "ReplayChunk")
            {
                liveForwardTask = Task.Run(() => workerHub!.ForwardStdout(liveChunk));
            }
        });
        workerHub = CreateWorkerHub(workers, sessions, replayCoordinator, new Dictionary<string, IClientProxy>
        {
            ["client-reattached"] = caller
        });
        workerHub.Context = new TestHubCallerContext("worker-conn-1");
        workerHub.Clients = new TestHubCallerClients(new RecordingClientProxy());
        var terminalHub = CreateTerminalHub(sessions, replayCoordinator, dispatcher, new FixedTimeProvider(detachedAtUtc.AddMinutes(4)));
        terminalHub.Context = new TestHubCallerContext("client-reattached", "user-1");
        terminalHub.Clients = new TestHubCallerClients(caller);

        var reattachResult = await InvokeAsync<ReattachSessionResult>(
            terminalHub,
            "ReattachSession",
            new ReattachSessionRequest(sessionId));

        reattachResult.Should().BeEquivalentTo(ReattachSessionResult.Success());
        liveForwardTask.Should().NotBeNull();
        await liveForwardTask!;

        // Live chunk should appear AFTER ReplayCompleted (snapshot is flushed first, then pendingQueue drains)
        caller.Invocations.Select(static invocation => invocation.Method).Should().Equal(
            "SessionReattached",
            "ReplayChunk",
            "ReplayCompleted",
            "StdoutChunk");
        caller.Invocations[3].Arguments[0].Should().BeEquivalentTo(liveChunk);
    }

    [Fact]
    public async Task ReattachSession_WhenReplayDeliveryFails_RevertsSessionToAttached()
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = TestSessionFactory.CreateCoordinator(workers);
        var replayCoordinator = new ReplayCoordinator();
        var dispatcher = new ScrollbackWorkerCommandDispatcher(
            new TerminalChunk("dummy", "stdout", [0xAA]));
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var detachedAtUtc = new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero);

        await sessions.DetachSessionAsync("user-1", sessionId, detachedAtUtc, CancellationToken.None);

        var hub = CreateTerminalHub(sessions, replayCoordinator, dispatcher, new FixedTimeProvider(detachedAtUtc.AddMinutes(4)));
        hub.Context = new TestHubCallerContext("client-reattached", "user-1");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy((method, _) =>
        {
            if (method == "ReplayChunk")
            {
                throw new InvalidOperationException("replay failed");
            }
        }));

        var action = () => InvokeAsync<ReattachSessionResult>(
            hub,
            "ReattachSession",
            new ReattachSessionRequest(sessionId));

        await action.Should().ThrowAsync<InvalidOperationException>()
            .WithMessage("replay failed");
        sessions.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Attached);
        session.AttachedClientConnectionId.Should().BeNull();
        session.ReplayPending.Should().BeFalse();
        session.LeaseExpiresAtUtc.Should().BeNull();
    }

    private static TerminalHub CreateTerminalHub(
        ISessionCoordinator sessions,
        ReplayCoordinator replayCoordinator,
        IWorkerCommandDispatcher dispatcher,
        TimeProvider timeProvider)
        => (TerminalHub)Activator.CreateInstance(
            typeof(TerminalHub),
            sessions,
            replayCoordinator,
            timeProvider,
            dispatcher,
            new SessionLaunchCoordinator(sessions, dispatcher, new ScrollbackSettings(), TestSessionFactory.CreatePreferenceService()),
            new NoOpStatsService(),
            NullLogger<TerminalHub>.Instance)!;

    private static WorkerHub CreateWorkerHub(
        IWorkerRegistry workers,
        ISessionCoordinator sessions,
        ReplayCoordinator replayCoordinator,
        IReadOnlyDictionary<string, IClientProxy>? terminalClients = null)
        => (WorkerHub)Activator.CreateInstance(
            typeof(WorkerHub),
            workers,
            sessions,
            replayCoordinator,
            new NullAuditLogStore(),
            new TestHubContext<TerminalHub>(terminalClients ?? new Dictionary<string, IClientProxy>()),
            new NoOpStatsService(),
            new NoOpSessionStatsService(),
            NullLogger<WorkerHub>.Instance)!;

    private static async Task<T> InvokeAsync<T>(object instance, string methodName, params object?[] arguments)
    {
        var method = instance.GetType().GetMethod(methodName);
        method.Should().NotBeNull($"expected {instance.GetType().Name}.{methodName} to exist");

        var task = (Task<T>)method!.Invoke(instance, arguments)!;
        return await task;
    }

    private sealed class ScrollbackWorkerCommandDispatcher : IWorkerCommandDispatcher
    {
        private readonly (string Stream, byte[] Payload)[] _scrollback;

        public ScrollbackWorkerCommandDispatcher(params TerminalChunk[] scrollback)
            => _scrollback = scrollback.Select(c => (c.Stream, c.Payload)).ToArray();

        public Task StartSessionAsync(string workerConnectionId, StartSessionCommand command, CancellationToken cancellationToken)
            => Task.CompletedTask;

        public Task WriteInputAsync(string workerConnectionId, WriteInputFrame frame, CancellationToken cancellationToken)
            => Task.CompletedTask;

        public Task ProbeLatencyAsync(string workerConnectionId, LatencyProbeFrame frame, CancellationToken cancellationToken)
            => Task.CompletedTask;

        public Task ResizeSessionAsync(string workerConnectionId, ResizePtyRequest request, CancellationToken cancellationToken)
            => Task.CompletedTask;

        public Task CloseSessionAsync(string workerConnectionId, CloseSessionRequest request, CancellationToken cancellationToken)
            => Task.CompletedTask;

        public Task UpgradeWorkerAsync(string workerConnectionId, UpgradeWorkerCommand command, CancellationToken cancellationToken)
            => Task.CompletedTask;

        public Task<IReadOnlyList<TerminalChunk>> RequestScrollbackAsync(string workerConnectionId, string sessionId, CancellationToken cancellationToken)
            => Task.FromResult<IReadOnlyList<TerminalChunk>>(
                _scrollback.Select(item => new TerminalChunk(sessionId, item.Stream, item.Payload)).ToArray());
    }
}
