using System.Collections.Concurrent;
using System.Reflection;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Tests.Hubs;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Sessions;

public sealed class DetachedSessionExpiryServiceTests
{
    [Fact]
    public async Task BackgroundService_DetachedSessionsNoLongerExpire()
    {
        // Detach now only clears the client connection; sessions stay Attached.
        // The background service only expires Recovering sessions.
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCoordinator = new ReplayCoordinator();
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var detachedAtUtc = new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero);

        await sessions.DetachSessionAsync("user-1", sessionId, detachedAtUtc, CancellationToken.None);

        var service = CreateService(sessions, replayCoordinator, new FixedTimeProvider(detachedAtUtc.AddMinutes(6)));

        await service.StartAsync(CancellationToken.None);
        await Task.Delay(100);
        await service.StopAsync(CancellationToken.None);

        sessions.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Attached);
        session.AttachedClientConnectionId.Should().BeNull();
    }

    [Fact]
    public async Task ExecuteAsync_WhenStoppingTokenIsCancelledDuringDelay_StopsCleanly()
    {
        var workers = new InMemoryWorkerRegistry();
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCoordinator = new ReplayCoordinator();
        var service = CreateService(sessions, replayCoordinator, TimeProvider.System);
        var executeAsync = service.GetType().GetMethod("ExecuteAsync", BindingFlags.Instance | BindingFlags.NonPublic);
        executeAsync.Should().NotBeNull();
        using var cts = new CancellationTokenSource();

        var executeTask = (Task)executeAsync!.Invoke(service, [cts.Token])!;

        await Task.Delay(100);
        cts.Cancel();

        Func<Task> act = async () => await executeTask;

        await act.Should().NotThrowAsync();
    }

    [Fact]
    public async Task BackgroundService_ExpiresRecoveringSessionsAfterTimeout()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCoordinator = new ReplayCoordinator();

        // Manually inject a Recovering session via reflection
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var sessionsDict = (ConcurrentDictionary<string, SessionRecord>)typeof(InMemorySessionCoordinator)
            .GetField("_sessions", BindingFlags.Instance | BindingFlags.NonPublic)!
            .GetValue(sessions)!;
        sessionsDict[sessionId] = sessionsDict[sessionId] with
        {
            AttachmentState = SessionAttachmentState.Recovering,
            LastActivityAtUtc = new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero)
        };

        var service = CreateService(sessions, replayCoordinator, new FixedTimeProvider(new DateTimeOffset(2025, 1, 1, 12, 2, 0, TimeSpan.Zero)));

        await service.StartAsync(CancellationToken.None);
        await Task.Delay(100);
        await service.StopAsync(CancellationToken.None);

        sessions.TryGetSession(sessionId, out var expiredSession).Should().BeTrue();
        expiredSession.AttachmentState.Should().Be(SessionAttachmentState.Expired);
        expiredSession.ExitReason.Should().Be("recovery-timeout");
    }

    private static IHostedService CreateService(ISessionCoordinator sessions, ReplayCoordinator replayCoordinator, TimeProvider timeProvider)
        => new DetachedSessionExpiryService(sessions, replayCoordinator, timeProvider, NullLogger<DetachedSessionExpiryService>.Instance);
}
