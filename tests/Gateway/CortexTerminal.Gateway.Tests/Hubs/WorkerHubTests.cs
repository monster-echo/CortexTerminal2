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

public sealed class WorkerHubTests
{
    [Fact]
    public async Task ForwardStdout_AfterSignalRSessionCreation_FansOutToCreatingClient()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCoordinator = new ReplayCoordinator();
        var terminalHub = CreateTerminalHub(sessions, replayCoordinator, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;
        var client = new RecordingClientProxy();
        var workerHub = CreateWorkerHub(workers, sessions, replayCoordinator, new Dictionary<string, IClientProxy>
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
    public async Task ForwardStdout_WhenReplayPending_EnqueuesToPendingQueueWithoutFanOut()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCoordinator = new ReplayCoordinator();
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var detachedAtUtc = new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero);

        await sessions.DetachSessionAsync("user-1", sessionId, detachedAtUtc, CancellationToken.None);
        // BeginReplay before ReattachSessionAsync ensures pendingQueue exists before ReplayPending flips
        replayCoordinator.BeginReplay(sessionId, "client-1");
        await sessions.ReattachSessionAsync("user-1", new ReattachSessionRequest(sessionId), "client-1", detachedAtUtc.AddMinutes(1), CancellationToken.None);

        var client = new RecordingClientProxy();
        var hub = CreateWorkerHub(workers, sessions, replayCoordinator, new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });
        hub.Context = new TestHubCallerContext("worker-conn-1");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var stdout = new TerminalChunk(sessionId, "stdout", [0x01, 0x02]);
        var stderr = new TerminalChunk(sessionId, "stderr", [0x03]);

        await hub.ForwardStdout(stdout);
        await hub.ForwardStderr(stderr);

        // Live fan-out is gated during replay; chunk sits in pendingQueue awaiting flush
        client.Invocations.Should().BeEmpty();

        // Flushing the pendingQueue should deliver both chunks in order to the client
        var flushed = new List<TerminalChunk>();
        await replayCoordinator.FlushPendingAsync(sessionId, "client-1", chunk =>
        {
            flushed.Add(chunk);
            return Task.CompletedTask;
        }, CancellationToken.None);
        flushed.Should().BeEquivalentTo([stdout, stderr], options => options.WithStrictOrdering());
    }

    [Fact]
    public async Task ForwardStdout_WithoutAttachedClient_DoesNotThrow()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCoordinator = new ReplayCoordinator();
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var hub = CreateWorkerHub(workers, sessions, replayCoordinator, new Dictionary<string, IClientProxy>());
        hub.Context = new TestHubCallerContext("worker-conn-1");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var chunk = new TerminalChunk(sessionId, "stdout", [0x2A]);

        await hub.Invoking(instance => instance.ForwardStdout(chunk)).Should().NotThrowAsync();
    }

    [Fact]
    public async Task ForwardStdout_FromWrongWorker_DoesNotFanOut()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCoordinator = new ReplayCoordinator();
        var terminalHub = CreateTerminalHub(sessions, replayCoordinator, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;
        var client = new RecordingClientProxy();
        var hub = CreateWorkerHub(workers, sessions, replayCoordinator, new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });
        hub.Context = new TestHubCallerContext("worker-conn-2");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        await hub.ForwardStdout(new TerminalChunk(sessionId, "stdout", [0x2A]));

        client.Invocations.Should().BeEmpty();
    }

    [Fact]
    public async Task ForwardLatencyProbe_AttachedClient_ReceivesAck()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCoordinator = new ReplayCoordinator();
        var terminalHub = CreateTerminalHub(sessions, replayCoordinator, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;
        var client = new RecordingClientProxy();
        var workerHub = CreateWorkerHub(workers, sessions, replayCoordinator, new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });
        workerHub.Context = new TestHubCallerContext("worker-conn-1");
        workerHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var probe = new LatencyProbeFrame(sessionId, "probe-1");

        await workerHub.ForwardLatencyProbe(probe);

        client.Invocations.Select(static invocation => invocation.Method).Should().Equal("LatencyProbeAck");
        client.Invocations[0].Arguments[0].Should().BeEquivalentTo(probe);
    }

    [Fact]
    public async Task SessionExited_UpdatesSessionStateAndNotifiesAttachedClient()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCoordinator = new ReplayCoordinator();
        var terminalHub = CreateTerminalHub(sessions, replayCoordinator, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;
        var client = new RecordingClientProxy();
        var workerHub = CreateWorkerHub(workers, sessions, replayCoordinator, new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });
        workerHub.Context = new TestHubCallerContext("worker-conn-1");
        workerHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        await workerHub.SessionExited(new SessionExited(sessionId, 0, "completed"));

        sessions.TryGetSession(sessionId, out _).Should().BeFalse();
        client.Invocations.Should().ContainSingle(invocation => invocation.Method == "SessionExited");
    }

    [Fact]
    public async Task RegisterWorker_RebindsActiveSessionsToLatestConnection()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCoordinator = new ReplayCoordinator();
        var terminalHub = CreateTerminalHub(sessions, replayCoordinator, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;
        var workerHub = CreateWorkerHub(workers, sessions, replayCoordinator, new Dictionary<string, IClientProxy>());
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
        var replayCoordinator = new ReplayCoordinator();
        var terminalHub = CreateTerminalHub(sessions, replayCoordinator, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;
        var client = new RecordingClientProxy();
        var workerHub = CreateWorkerHub(workers, sessions, replayCoordinator, new Dictionary<string, IClientProxy>
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
        ReplayCoordinator replayCoordinator,
        IReadOnlyDictionary<string, IClientProxy> terminalClients)
        => (WorkerHub)Activator.CreateInstance(
            typeof(WorkerHub),
            workers,
            sessions,
            replayCoordinator,
            new InMemoryAuditLogStore(),
            new TestHubContext<TerminalHub>(terminalClients),
            new NoOpStatsService(),
            NullLogger<WorkerHub>.Instance)!;

    private static TerminalHub CreateTerminalHub(ISessionCoordinator sessions, ReplayCoordinator replayCoordinator, TimeProvider timeProvider)
        => (TerminalHub)Activator.CreateInstance(
            typeof(TerminalHub),
            sessions,
            replayCoordinator,
            timeProvider,
            new NoOpWorkerCommandDispatcher(),
            new SessionLaunchCoordinator(sessions, new NoOpWorkerCommandDispatcher()),
            new NoOpStatsService(),
            NullLogger<TerminalHub>.Instance)!;

    [Fact]
    public async Task OnDisconnectedAsync_ExpiresAttachedSessionsAndNotifiesClients()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCoordinator = new ReplayCoordinator();
        var terminalHub = CreateTerminalHub(sessions, replayCoordinator, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;

        var client = new RecordingClientProxy();
        var workerHub = CreateWorkerHub(workers, sessions, replayCoordinator, new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });
        workerHub.Context = new TestHubCallerContext("worker-conn-1");
        workerHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        await workerHub.OnDisconnectedAsync(null);

        sessions.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Expired);
        session.ExitReason.Should().Be("worker-offline");
        session.AttachedClientConnectionId.Should().BeNull();

        client.Invocations.Should().ContainSingle(i => i.Method == "SessionExpired");
        var expiredEvent = client.Invocations[0].Arguments[0].Should().BeOfType<SessionExpiredEvent>().Subject;
        expiredEvent.SessionId.Should().Be(sessionId);
        expiredEvent.Reason.Should().Be("worker-offline");

        workers.TryGetWorker("worker-1", out _).Should().BeFalse();
    }

    [Fact]
    public async Task OnDisconnectedAsync_DoesNotExpireSessionsForOtherWorkers()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        workers.Register("worker-2", "worker-conn-2");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCoordinator = new ReplayCoordinator();
        var terminalHub = CreateTerminalHub(sessions, replayCoordinator, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;

        var client = new RecordingClientProxy();
        var workerHub = CreateWorkerHub(workers, sessions, replayCoordinator, new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });
        workerHub.Context = new TestHubCallerContext("worker-conn-2");
        workerHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        await workerHub.OnDisconnectedAsync(null);

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
        var replayCoordinator = new ReplayCoordinator();
        var terminalHub = CreateTerminalHub(sessions, replayCoordinator, TimeProvider.System);
        terminalHub.Context = new TestHubCallerContext("client-1", "user-1");
        terminalHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40));
        var sessionId = createResult.Response!.SessionId;

        var workerHub2 = CreateWorkerHub(workers, sessions, replayCoordinator, new Dictionary<string, IClientProxy>());
        workerHub2.Context = new TestHubCallerContext("worker-conn-2", "user-1");
        workerHub2.Clients = new TestHubCallerClients(new RecordingClientProxy());
        workerHub2.RegisterWorker("worker-1");

        var workerHub1 = CreateWorkerHub(workers, sessions, replayCoordinator, new Dictionary<string, IClientProxy>());
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
        var replayCoordinator = new ReplayCoordinator();
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;

        var workerHub = CreateWorkerHub(workers, sessions, replayCoordinator, new Dictionary<string, IClientProxy>());
        workerHub.Context = new TestHubCallerContext("worker-conn-1");
        workerHub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        await workerHub.Invoking(hub => hub.OnDisconnectedAsync(null)).Should().NotThrowAsync();

        sessions.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Expired);
        session.ExitReason.Should().Be("worker-offline");
    }
}
