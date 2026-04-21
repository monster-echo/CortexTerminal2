using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
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
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), CancellationToken.None);
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
            new ReattachSessionRequest(sessionId),
            CancellationToken.None);

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

    private static TerminalHub CreateTerminalHub(ISessionCoordinator sessions, IReplayCache replayCache, TimeProvider timeProvider)
        => (TerminalHub)Activator.CreateInstance(typeof(TerminalHub), sessions, replayCache, timeProvider)!;

    private static async Task<T> InvokeAsync<T>(object instance, string methodName, params object?[] arguments)
    {
        var method = instance.GetType().GetMethod(methodName);
        method.Should().NotBeNull($"expected {instance.GetType().Name}.{methodName} to exist");

        var task = (Task<T>)method!.Invoke(instance, arguments)!;
        return await task;
    }
}
