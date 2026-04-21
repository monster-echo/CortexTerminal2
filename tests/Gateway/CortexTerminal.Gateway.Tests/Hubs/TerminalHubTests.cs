using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.AspNetCore.SignalR;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Hubs;

public sealed class TerminalHubTests
{
    [Fact]
    public void WorkerRegistry_RegisterAndRetrieve_Works()
    {
        var registry = new InMemoryWorkerRegistry();
        registry.Register("w-1", "conn-abc");

        registry.TryGetLeastBusy(out var worker).Should().BeTrue();
        worker.WorkerId.Should().Be("w-1");
        worker.ConnectionId.Should().Be("conn-abc");
    }

    [Fact]
    public void WorkerRegistry_Empty_ReturnsFalse()
    {
        var registry = new InMemoryWorkerRegistry();
        registry.TryGetLeastBusy(out _).Should().BeFalse();
    }

    [Fact]
    public void WorkerRegistry_Unregister_RemovesWorker()
    {
        var registry = new InMemoryWorkerRegistry();
        registry.Register("w-1", "conn-abc");
        registry.Unregister("w-1");

        registry.TryGetLeastBusy(out _).Should().BeFalse();
    }

    [Fact]
    public async Task WriteInput_WhenSessionIsDetached_ThrowsHubException()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-1", CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        await sessions.DetachSessionAsync("user-1", sessionId, new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero), CancellationToken.None);

        var hub = CreateTerminalHub(sessions, replayCache, TimeProvider.System);
        hub.Context = new TestHubCallerContext("client-1", "user-1");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy(), new Dictionary<string, IClientProxy>
        {
            ["worker-conn-1"] = new RecordingClientProxy()
        });

        var action = () => hub.WriteInput(new WriteInputFrame(sessionId, [0x01]));

        await action.Should().ThrowAsync<HubException>()
            .WithMessage("*attached*");
    }

    [Fact]
    public async Task WriteInput_WhenCallerDoesNotOwnAttachedSession_ThrowsHubException()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-1", CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var workerClient = new RecordingClientProxy();

        var hub = CreateTerminalHub(sessions, replayCache, TimeProvider.System);
        hub.Context = new TestHubCallerContext("client-2", "user-1");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy(), new Dictionary<string, IClientProxy>
        {
            ["worker-conn-1"] = workerClient
        });

        var action = () => hub.WriteInput(new WriteInputFrame(sessionId, [0x01]));

        await action.Should().ThrowAsync<HubException>()
            .WithMessage("*different client*");
        workerClient.Invocations.Should().BeEmpty();
    }

    private static TerminalHub CreateTerminalHub(ISessionCoordinator sessions, IReplayCache replayCache, TimeProvider timeProvider)
        => (TerminalHub)Activator.CreateInstance(typeof(TerminalHub), sessions, replayCache, timeProvider, new NoOpWorkerCommandDispatcher())!;
}
