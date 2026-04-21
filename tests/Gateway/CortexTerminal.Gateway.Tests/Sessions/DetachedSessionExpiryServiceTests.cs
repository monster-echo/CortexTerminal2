using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Tests.Hubs;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.Extensions.Hosting;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Sessions;

public sealed class DetachedSessionExpiryServiceTests
{
    [Fact]
    public async Task BackgroundService_ExpiresDetachedSessionsAndClearsReplay()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var sessions = new InMemorySessionCoordinator(workers);
        var replayCache = new ReplayCache(1024);
        var createResult = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var detachedAtUtc = new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero);

        await sessions.DetachSessionAsync("user-1", sessionId, detachedAtUtc, CancellationToken.None);
        replayCache.Append(new ReplayChunk(sessionId, "stdout", [0x01]));

        var service = CreateService(sessions, replayCache, new FixedTimeProvider(detachedAtUtc.AddMinutes(6)));

        await service.StartAsync(CancellationToken.None);
        await Task.Delay(100);
        await service.StopAsync(CancellationToken.None);

        sessions.TryGetSession(sessionId, out var expiredSession).Should().BeTrue();
        expiredSession.AttachmentState.Should().Be(SessionAttachmentState.Expired);
        replayCache.GetSnapshot(sessionId).Should().BeEmpty();
    }

    private static IHostedService CreateService(ISessionCoordinator sessions, IReplayCache replayCache, TimeProvider timeProvider)
    {
        var type = typeof(InMemorySessionCoordinator).Assembly.GetType("CortexTerminal.Gateway.Sessions.DetachedSessionExpiryService");
        type.Should().NotBeNull("expected DetachedSessionExpiryService to exist");
        return (IHostedService)Activator.CreateInstance(type!, sessions, replayCache, timeProvider)!;
    }
}
