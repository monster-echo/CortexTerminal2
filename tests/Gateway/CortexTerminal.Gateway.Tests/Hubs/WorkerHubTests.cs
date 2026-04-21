using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.AspNetCore.SignalR;
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

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40), CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var client = new RecordingClientProxy();
        var workerHub = CreateWorkerHub(workers, sessions, replayCache);
        workerHub.Context = new TestHubCallerContext("worker-conn-1");
        workerHub.Clients = new TestHubCallerClients(new RecordingClientProxy(), new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });

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
        var hub = CreateWorkerHub(workers, sessions, replayCache);
        hub.Context = new TestHubCallerContext("worker-conn-1");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy(), new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });

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
        var hub = CreateWorkerHub(workers, sessions, replayCache);
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

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40), CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var client = new RecordingClientProxy();
        var hub = CreateWorkerHub(workers, sessions, replayCache);
        hub.Context = new TestHubCallerContext("worker-conn-2");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy(), new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });

        await hub.ForwardStdout(new TerminalChunk(sessionId, "stdout", [0x2A]));

        replayCache.GetSnapshot(sessionId).Should().BeEmpty();
        client.Invocations.Should().BeEmpty();
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

        var createResult = await terminalHub.CreateSession(new CreateSessionRequest("shell", 120, 40), CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var client = new RecordingClientProxy();
        var workerHub = CreateWorkerHub(workers, sessions, replayCache);
        workerHub.Context = new TestHubCallerContext("worker-conn-1");
        workerHub.Clients = new TestHubCallerClients(new RecordingClientProxy(), new Dictionary<string, IClientProxy>
        {
            ["client-1"] = client
        });

        await workerHub.SessionExited(new SessionExited(sessionId, 0, "completed"));

        sessions.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Exited);
        session.ExitCode.Should().Be(0);
        session.ExitReason.Should().Be("completed");
        client.Invocations.Should().ContainSingle(invocation => invocation.Method == "SessionExited");
        replayCache.GetSnapshot(sessionId).Should().BeEmpty();
    }

    private static WorkerHub CreateWorkerHub(IWorkerRegistry workers, ISessionCoordinator sessions, IReplayCache replayCache)
        => (WorkerHub)Activator.CreateInstance(typeof(WorkerHub), workers, sessions, replayCache)!;

    private static TerminalHub CreateTerminalHub(ISessionCoordinator sessions, IReplayCache replayCache, TimeProvider timeProvider)
        => (TerminalHub)Activator.CreateInstance(typeof(TerminalHub), sessions, replayCache, timeProvider, new NoOpWorkerCommandDispatcher())!;
}
