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

public sealed class TerminalHubReconnectTests
{
    [Fact]
    public async Task ReattachSession_SendsReattachedReplayAndCompletionInOrder()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var detachedAtUtc = new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero);

        await sessions.DetachSessionAsync("user-1", sessionId, detachedAtUtc, CancellationToken.None);
        replayCache.Append(new ReplayChunk(sessionId, "stdout", [0x01, 0x02]));
        replayCache.Append(new ReplayChunk(sessionId, "stderr", [0x03]));

        var caller = new RecordingClientProxy();
        var hub = CreateTerminalHub(sessions, replayCache, new FixedTimeProvider(detachedAtUtc.AddMinutes(4)));
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
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var detachedAtUtc = new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero);

        await sessions.DetachSessionAsync("user-1", sessionId, detachedAtUtc, CancellationToken.None);
        replayCache.Append(new ReplayChunk(sessionId, "stdout", [0xAA]));

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
        workerHub = CreateWorkerHub(workers, sessions, replayCache, new Dictionary<string, IClientProxy>
        {
            ["client-reattached"] = caller
        });
        workerHub.Context = new TestHubCallerContext("worker-conn-1");
        workerHub.Clients = new TestHubCallerClients(new RecordingClientProxy());
        var terminalHub = CreateTerminalHub(sessions, replayCache, new FixedTimeProvider(detachedAtUtc.AddMinutes(4)));
        terminalHub.Context = new TestHubCallerContext("client-reattached", "user-1");
        terminalHub.Clients = new TestHubCallerClients(caller);

        var reattachResult = await InvokeAsync<ReattachSessionResult>(
            terminalHub,
            "ReattachSession",
            new ReattachSessionRequest(sessionId));

        reattachResult.Should().BeEquivalentTo(ReattachSessionResult.Success());
        liveForwardTask.Should().NotBeNull();
        await liveForwardTask!;

        caller.Invocations.Select(static invocation => invocation.Method).Should().Equal(
            "SessionReattached",
            "ReplayChunk",
            "ReplayCompleted",
            "StdoutChunk");
        caller.Invocations[3].Arguments[0].Should().BeEquivalentTo(liveChunk);
    }

    [Fact]
    public async Task ReattachSession_WhenReplayDeliveryFails_RevertsSessionToDetachedGracePeriod()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var detachedAtUtc = new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero);

        await sessions.DetachSessionAsync("user-1", sessionId, detachedAtUtc, CancellationToken.None);
        replayCache.Append(new ReplayChunk(sessionId, "stdout", [0xAA]));

        var hub = CreateTerminalHub(sessions, replayCache, new FixedTimeProvider(detachedAtUtc.AddMinutes(4)));
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
        session.AttachmentState.Should().Be(SessionAttachmentState.DetachedGracePeriod);
        session.AttachedClientConnectionId.Should().BeNull();
        session.ReplayPending.Should().BeFalse();
        session.LeaseExpiresAtUtc.Should().NotBeNull();
    }

    private static TerminalHub CreateTerminalHub(ISessionCoordinator sessions, IReplayCache replayCache, TimeProvider timeProvider)
        => (TerminalHub)Activator.CreateInstance(
            typeof(TerminalHub),
            sessions,
            replayCache,
            timeProvider,
            new NoOpWorkerCommandDispatcher(),
            new SessionLaunchCoordinator(sessions, new NoOpWorkerCommandDispatcher()))!;

    private static WorkerHub CreateWorkerHub(
        IWorkerRegistry workers,
        ISessionCoordinator sessions,
        IReplayCache replayCache,
        IReadOnlyDictionary<string, IClientProxy>? terminalClients = null)
        => (WorkerHub)Activator.CreateInstance(
            typeof(WorkerHub),
            workers,
            sessions,
            replayCache,
            new InMemoryAuditLogStore(),
            new TestHubContext<TerminalHub>(terminalClients ?? new Dictionary<string, IClientProxy>()),
            NullLogger<WorkerHub>.Instance)!;

    private static async Task<T> InvokeAsync<T>(object instance, string methodName, params object?[] arguments)
    {
        var method = instance.GetType().GetMethod(methodName);
        method.Should().NotBeNull($"expected {instance.GetType().Name}.{methodName} to exist");

        var task = (Task<T>)method!.Invoke(instance, arguments)!;
        return await task;
    }
}
