using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Audit;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Tests.Workers;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Hubs;

public sealed class WorkerHubTests
{
    [Fact]
    public async Task ForwardStdout_AfterSignalRSessionCreation_FansOutToCreatingClient()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var terminalHub = CreateTerminalHub(sessions, replayCache, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;
        var client = new RecordingClientProxy();
        var workerHub = CreateWorkerHub(workers, sessions, replayCache, new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });
        workerHub.Context = new TestHubCallerContext("worker-conn-1");
        workerHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var chunk = new TerminalChunk(sessionId, "stdout", [0x2A]);

        await workerHub.ForwardStdout(chunk);

        client.Invocations.Select(static invocation => invocation.Method).Should().Equal("StdoutChunk");
        client.Invocations[0].Arguments[0].Should().BeEquivalentTo(chunk);
    }

    [Fact]
    public async Task ForwardOutput_BuffersReplayWithoutLiveFanOutWhileReplayIsPending()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var detachedAtUtc = new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero);

        await sessions.DetachSessionAsync("user-1", sessionId, detachedAtUtc, CancellationToken.None);
        await sessions.ReattachSessionAsync("user-1", new ReattachSessionRequest(sessionId), "client-1", detachedAtUtc.AddMinutes(1), CancellationToken.None);

        var client = new RecordingClientProxy((_, _) =>
        {
            replayCache.GetSnapshot(sessionId).Should().NotBeEmpty();
        });
        var hub = CreateWorkerHub(workers, sessions, replayCache, new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });
        hub.Context = new TestHubCallerContext("worker-conn-1");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var stdout = new TerminalChunk(sessionId, "stdout", [0x01, 0x02]);
        var stderr = new TerminalChunk(sessionId, "stderr", [0x03]);

        await hub.ForwardStdout(stdout);
        await hub.ForwardStderr(stderr);

        replayCache.GetSnapshot(sessionId).Should().BeEquivalentTo(
        [
            new ReplayChunk(sessionId, "stdout", [0x01, 0x02]),
            new ReplayChunk(sessionId, "stderr", [0x03])
        ],
        options => options.WithStrictOrdering());
        client.Invocations.Should().BeEmpty();
    }

    [Fact]
    public async Task ForwardStdout_WithoutAttachedClient_DoesNotThrowAndStillCachesReplay()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var hub = CreateWorkerHub(workers, sessions, replayCache, new Dictionary<string, IClientProxy>());
        hub.Context = new TestHubCallerContext("worker-conn-1");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var chunk = new TerminalChunk(sessionId, "stdout", [0x2A]);

        await hub.Invoking(instance => instance.ForwardStdout(chunk)).Should().NotThrowAsync();
        replayCache.GetSnapshot(sessionId).Should().BeEquivalentTo(
            [new ReplayChunk(sessionId, "stdout", [0x2A])],
            options => options.WithStrictOrdering());
    }

    [Fact]
    public async Task ForwardStdout_FromWrongWorker_DoesNotCacheOrFanOut()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var terminalHub = CreateTerminalHub(sessions, replayCache, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;
        var client = new RecordingClientProxy();
        var hub = CreateWorkerHub(workers, sessions, replayCache, new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });
        hub.Context = new TestHubCallerContext("worker-conn-2");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        await hub.ForwardStdout(new TerminalChunk(sessionId, "stdout", [0x2A]));

        replayCache.GetSnapshot(sessionId).Should().BeEmpty();
        client.Invocations.Should().BeEmpty();
    }

    [Fact]
    public async Task ForwardLatencyProbe_AttachedClient_ReceivesAckWithoutReplayBuffering()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var terminalHub = CreateTerminalHub(sessions, replayCache, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;
        var client = new RecordingClientProxy();
        var workerHub = CreateWorkerHub(workers, sessions, replayCache, new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });
        workerHub.Context = new TestHubCallerContext("worker-conn-1");
        workerHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var probe = new LatencyProbeFrame(sessionId, "probe-1");

        await workerHub.ForwardLatencyProbe(probe);

        client.Invocations.Select(static invocation => invocation.Method).Should().Equal("LatencyProbeAck");
        client.Invocations[0].Arguments[0].Should().BeEquivalentTo(probe);
        replayCache.GetSnapshot(sessionId).Should().BeEmpty();
    }

    [Fact]
    public async Task SessionExited_UpdatesSessionStateAndNotifiesAttachedClient()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var terminalHub = CreateTerminalHub(sessions, replayCache, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;
        var client = new RecordingClientProxy();
        var workerHub = CreateWorkerHub(workers, sessions, replayCache, new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });
        workerHub.Context = new TestHubCallerContext("worker-conn-1");
        workerHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        await workerHub.SessionExited(new SessionExited(sessionId, 0, "completed"));

        sessions.TryGetSession(sessionId, out _).Should().BeFalse();
        client.Invocations.Should().ContainSingle(invocation => invocation.Method == "SessionExited");
        replayCache.GetSnapshot(sessionId).Should().BeEmpty();
    }

    [Fact]
    public async Task RegisterWorker_RebindsActiveSessionsToLatestConnection()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var terminalHub = CreateTerminalHub(sessions, replayCache, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;
        var workerHub = CreateWorkerHub(workers, sessions, replayCache, new Dictionary<string, IClientProxy>());
        workerHub.Context = new TestHubCallerContext("worker-conn-2", "user-1");
        workerHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        workerHub.RegisterWorker("worker-1");

        sessions.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.WorkerConnectionId.Should().Be("worker-conn-2");
    }

    [Fact]
    public async Task SessionExited_AfterWorkerReconnect_UsesReboundConnection()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var terminalHub = CreateTerminalHub(sessions, replayCache, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;
        var client = new RecordingClientProxy();
        var workerHub = CreateWorkerHub(workers, sessions, replayCache, new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });
        workerHub.Context = new TestHubCallerContext("worker-conn-2", "user-1");
        workerHub.Clients = new TestHubCallerClients(new RecordingClientProxy());
        workerHub.RegisterWorker("worker-1");

        await workerHub.SessionExited(new SessionExited(sessionId, 137, "terminated-by-user"));

        sessions.TryGetSession(sessionId, out _).Should().BeFalse();
        client.Invocations.Should().ContainSingle(invocation => invocation.Method == "SessionExited");
    }

    private static WorkerHub CreateWorkerHub(
        IWorkerRegistry workers,
        ISessionCoordinator sessions,
        IReplayCache replayCache,
        IReadOnlyDictionary<string, IClientProxy> terminalClients)
        => (WorkerHub)Activator.CreateInstance(
            typeof(WorkerHub),
            workers,
            sessions,
            replayCache,
            new InMemoryAuditLogStore(),
            new TestHubContext<TerminalHub>(terminalClients),
            NullLogger<WorkerHub>.Instance)!;

    private static TerminalHub CreateTerminalHub(ISessionCoordinator sessions, IReplayCache replayCache, TimeProvider timeProvider)
        => (TerminalHub)Activator.CreateInstance(
            typeof(TerminalHub),
            sessions,
            replayCache,
            timeProvider,
            new NoOpWorkerCommandDispatcher(),
            new SessionLaunchCoordinator(sessions, new NoOpWorkerCommandDispatcher()))!;

    [Fact]
    public async Task OnDisconnectedAsync_ExpiresAttachedSessionsAndNotifiesClients()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var terminalHub = CreateTerminalHub(sessions, replayCache, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;

        // Add some replay data to verify it gets cleared
        await replayCache.AppendAsync(new ReplayChunk(sessionId, "stdout", [0x01]), CancellationToken.None);
        replayCache.GetSnapshot(sessionId).Should().NotBeEmpty();

        var client = new RecordingClientProxy();
        var workerHub = CreateWorkerHub(workers, sessions, replayCache, new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });
        workerHub.Context = new TestHubCallerContext("worker-conn-1");
        workerHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        // Worker disconnects
        await workerHub.OnDisconnectedAsync(null);

        // Session should be expired
        sessions.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Expired);
        session.ExitReason.Should().Be("worker-offline");
        session.AttachedClientConnectionId.Should().BeNull();

        // Client should have been notified
        client.Invocations.Should().ContainSingle(i => i.Method == "SessionExpired");
        var expiredEvent = client.Invocations[0].Arguments[0].Should().BeOfType<SessionExpiredEvent>().Subject;
        expiredEvent.SessionId.Should().Be(sessionId);
        expiredEvent.Reason.Should().Be("worker-offline");

        // Replay cache should be cleared
        replayCache.GetSnapshot(sessionId).Should().BeEmpty();

        // Worker should be unregistered
        workers.TryGetWorker("worker-1", out _).Should().BeFalse();
    }

    [Fact]
    public async Task OnDisconnectedAsync_DoesNotExpireSessionsForOtherWorkers()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        workers.Register("worker-2", "worker-conn-2");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var terminalHub = CreateTerminalHub(sessions, replayCache, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;

        var client = new RecordingClientProxy();
        var workerHub = CreateWorkerHub(workers, sessions, replayCache, new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });
        workerHub.Context = new TestHubCallerContext("worker-conn-2"); // Different worker disconnects
        workerHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        await workerHub.OnDisconnectedAsync(null);

        // Session owned by worker-1 should NOT be expired
        sessions.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Attached);
        client.Invocations.Should().BeEmpty();
    }

    [Fact]
    public async Task OnDisconnectedAsync_DoesNotExpireReboundSessions()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var terminalHub = CreateTerminalHub(sessions, replayCache, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;

        // Worker reconnects with new connection, sessions get rebound
        var workerHub2 = CreateWorkerHub(workers, sessions, replayCache, new Dictionary<string, IClientProxy>());
        workerHub2.Context = new TestHubCallerContext("worker-conn-2", "user-1");
        workerHub2.Clients = new TestHubCallerClients(new RecordingClientProxy());
        workerHub2.RegisterWorker("worker-1");

        // Old connection disconnects - should NOT expire rebound sessions
        var workerHub1 = CreateWorkerHub(workers, sessions, replayCache, new Dictionary<string, IClientProxy>());
        workerHub1.Context = new TestHubCallerContext("worker-conn-1");
        workerHub1.Clients = new TestHubCallerClients(new RecordingClientProxy());

        await workerHub1.OnDisconnectedAsync(null);

        sessions.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Attached);
        session.WorkerConnectionId.Should().Be("worker-conn-2");
    }

    [Fact]
    public async Task OnDisconnectedAsync_HandlesSessionsWithoutAttachedClient()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        // Create session without client connection
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;

        var workerHub = CreateWorkerHub(workers, sessions, replayCache, new Dictionary<string, IClientProxy>());
        workerHub.Context = new TestHubCallerContext("worker-conn-1");
        workerHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        // Should not throw even without attached client
        await workerHub.Invoking(hub => hub.OnDisconnectedAsync(null)).Should().NotThrowAsync();

        sessions.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Expired);
        session.ExitReason.Should().Be("worker-offline");
    }
}
