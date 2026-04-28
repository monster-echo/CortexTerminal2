using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Tests.Workers;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.AspNetCore.SignalR;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Hubs;

public sealed class TerminalHubWorkerDispatchTests
{
    [Fact]
    public async Task CreateSession_DispatchesStartSessionToOwningWorker()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var workerClient = new RecordingClientProxy();
        var dispatcher = new SignalRWorkerCommandDispatcher(new TestHubContext<WorkerHub>(new Dictionary<string, IClientProxy>
        {
            ["worker-conn-1"] = workerClient
        }));
        var hub = CreateTerminalHub(sessions, replayCache, TimeProvider.System, dispatcher);
        hub.Context = new TestHubCallerContext("client-1", "user-1");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var result = await hub.CreateSession(new CreateSessionRequest("shell", 120, 40));

        result.IsSuccess.Should().BeTrue();
        workerClient.Invocations.Should().ContainSingle(invocation => invocation.Method == "StartSession");
        workerClient.Invocations[0].Arguments[0].Should().BeOfType<StartSessionCommand>();
    }

    [Fact]
    public async Task CreateSession_WithSameClientRequestId_ReusesExistingSessionAndDispatchesOnce()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var workerClient = new RecordingClientProxy();
        var dispatcher = new SignalRWorkerCommandDispatcher(new TestHubContext<WorkerHub>(new Dictionary<string, IClientProxy>
        {
            ["worker-conn-1"] = workerClient
        }));
        var hub = CreateTerminalHub(sessions, replayCache, TimeProvider.System, dispatcher);
        hub.Context = new TestHubCallerContext("client-1", "user-1");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var first = await hub.CreateSession(new CreateSessionRequest("shell", 120, 40, "boot-1"));
        var second = await hub.CreateSession(new CreateSessionRequest("shell", 120, 40, "boot-1"));

        first.IsSuccess.Should().BeTrue();
        second.IsSuccess.Should().BeTrue();
        second.Response!.SessionId.Should().Be(first.Response!.SessionId);
        workerClient.Invocations.Should().ContainSingle(invocation => invocation.Method == "StartSession");
    }

    [Fact]
    public async Task CreateSession_WhenStartSessionDispatchFails_MarksSessionExitedAndReturnsFailure()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var dispatcher = new ThrowingWorkerCommandDispatcher("dispatch failed");
        var hub = CreateTerminalHub(sessions, replayCache, TimeProvider.System, dispatcher);
        hub.Context = new TestHubCallerContext("client-1", "user-1");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy());

        var result = await hub.CreateSession(new CreateSessionRequest("shell", 120, 40));

        result.IsSuccess.Should().BeFalse();
        result.ErrorCode.Should().Be("worker-start-dispatch-failed");
        GetSingleSession(sessions).AttachmentState.Should().Be(SessionAttachmentState.Exited);
        GetSingleSession(sessions).ExitReason.Should().Be("worker-start-dispatch-failed");
    }

    [Fact]
    public async Task ResizeSession_DispatchesToOwningWorkerOnly()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var workerClient = new RecordingClientProxy();
        var dispatcher = new SignalRWorkerCommandDispatcher(new TestHubContext<WorkerHub>(new Dictionary<string, IClientProxy>
        {
            ["worker-conn-1"] = workerClient
        }));
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-1", CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var hub = CreateTerminalHub(sessions, replayCache, TimeProvider.System, dispatcher);
        hub.Context = new TestHubCallerContext("client-1", "user-1");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy(), new Dictionary<string, IClientProxy>
        {
            ["worker-conn-1"] = workerClient
        });

        await hub.ResizeSession(new ResizePtyRequest(sessionId, 100, 50));

        workerClient.Invocations.Should().ContainSingle(invocation => invocation.Method == "ResizeSession");
    }

    [Fact]
    public async Task ProbeLatency_DispatchesToOwningWorkerOnly()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var workerClient = new RecordingClientProxy();
        var dispatcher = new SignalRWorkerCommandDispatcher(new TestHubContext<WorkerHub>(new Dictionary<string, IClientProxy>
        {
            ["worker-conn-1"] = workerClient
        }));
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-1", CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var hub = CreateTerminalHub(sessions, replayCache, TimeProvider.System, dispatcher);
        hub.Context = new TestHubCallerContext("client-1", "user-1");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy(), new Dictionary<string, IClientProxy>
        {
            ["worker-conn-1"] = workerClient
        });

        await hub.ProbeLatency(new LatencyProbeFrame(sessionId, "probe-1"));

        workerClient.Invocations.Should().ContainSingle(invocation => invocation.Method == "ProbeLatency");
        workerClient.Invocations[0].Arguments[0].Should().BeEquivalentTo(new LatencyProbeFrame(sessionId, "probe-1"));
    }

    [Fact]
    public async Task CloseSession_DispatchesToOwningWorkerOnly()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var workerClient = new RecordingClientProxy();
        var dispatcher = new SignalRWorkerCommandDispatcher(new TestHubContext<WorkerHub>(new Dictionary<string, IClientProxy>
        {
            ["worker-conn-1"] = workerClient
        }));
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-1", CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var hub = CreateTerminalHub(sessions, replayCache, TimeProvider.System, dispatcher);
        hub.Context = new TestHubCallerContext("client-1", "user-1");
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy(), new Dictionary<string, IClientProxy>
        {
            ["worker-conn-1"] = workerClient
        });

        await hub.CloseSession(new CloseSessionRequest(sessionId));

        workerClient.Invocations.Should().ContainSingle(invocation => invocation.Method == "CloseSession");
    }

    private static TerminalHub CreateTerminalHub(ISessionCoordinator sessions, IReplayCache replayCache, TimeProvider timeProvider, IWorkerCommandDispatcher dispatcher)
        => (TerminalHub)Activator.CreateInstance(
            typeof(TerminalHub),
            sessions,
            replayCache,
            timeProvider,
            dispatcher,
            new SessionLaunchCoordinator(sessions, dispatcher))!;

    private static SessionRecord GetSingleSession(InMemorySessionCoordinator coordinator)
    {
        var sessions = (System.Collections.Concurrent.ConcurrentDictionary<string, SessionRecord>)typeof(InMemorySessionCoordinator)
            .GetField("_sessions", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!
            .GetValue(coordinator)!;

        sessions.Values.Should().ContainSingle();
        return sessions.Values.Single();
    }
}
