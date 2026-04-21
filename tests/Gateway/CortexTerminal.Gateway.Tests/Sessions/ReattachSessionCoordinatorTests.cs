using System.Collections.Concurrent;
using System.Reflection;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Sessions;

public sealed class ReattachSessionCoordinatorTests
{
    [Fact]
    public async Task ReattachSessionAsync_AfterDetachWithinLease_ForSameUser_ReturnsSuccess()
    {
        var coordinator = CreateCoordinator();
        var createResult = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var detachedAtUtc = new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero);

        coordinator.TryGetSession(sessionId, out var createdSession).Should().BeTrue();
        createdSession.AttachmentState.Should().Be(SessionAttachmentState.Attached);

        await coordinator.DetachSessionAsync("user-1", sessionId, detachedAtUtc, CancellationToken.None);

        var result = await coordinator.ReattachSessionAsync(
            "user-1",
            new ReattachSessionRequest(sessionId),
            "client-2",
            detachedAtUtc.AddMinutes(4),
            CancellationToken.None);

        result.Should().BeEquivalentTo(ReattachSessionResult.Success());
        coordinator.TryGetSession(sessionId, out var reattachedSession).Should().BeTrue();
        reattachedSession.AttachmentState.Should().Be(SessionAttachmentState.Attached);
        reattachedSession.AttachedClientConnectionId.Should().Be("client-2");
        reattachedSession.LeaseExpiresAtUtc.Should().BeNull();
    }

    [Fact]
    public async Task ReattachSessionAsync_WhenAlreadyAttached_ReturnsAlreadyAttached()
    {
        var coordinator = CreateCoordinator();
        var createResult = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), CancellationToken.None);

        var result = await coordinator.ReattachSessionAsync(
            "user-1",
            new ReattachSessionRequest(createResult.Response!.SessionId),
            "client-2",
            new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero),
            CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.ErrorCode.Should().Be("session-already-attached");
    }

    [Fact]
    public async Task ReattachSessionAsync_WhenSessionBelongsToDifferentUser_ReturnsSessionNotFound()
    {
        var coordinator = CreateCoordinator();
        var createResult = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), CancellationToken.None);

        var result = await coordinator.ReattachSessionAsync(
            "user-2",
            new ReattachSessionRequest(createResult.Response!.SessionId),
            "client-2",
            new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero),
            CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.ErrorCode.Should().Be("session-not-found");
    }

    [Fact]
    public async Task ReattachSessionAsync_WhenLeaseExpired_ReturnsExpiredAndMarksSessionExpired()
    {
        var coordinator = CreateCoordinator();
        var createResult = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var detachedAtUtc = new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero);

        await coordinator.DetachSessionAsync("user-1", sessionId, detachedAtUtc, CancellationToken.None);

        var result = await coordinator.ReattachSessionAsync(
            "user-1",
            new ReattachSessionRequest(sessionId),
            "client-2",
            detachedAtUtc.AddMinutes(5).AddSeconds(1),
            CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.ErrorCode.Should().Be("session-expired");
        coordinator.TryGetSession(sessionId, out var expiredSession).Should().BeTrue();
        expiredSession.AttachmentState.Should().Be(SessionAttachmentState.Expired);
    }

    [Fact]
    public async Task ReattachSessionAsync_WhenDetachedLeaseIsMissing_ReturnsCorruptedStateError()
    {
        var coordinator = CreateCoordinator();
        var createResult = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var sessions = GetSessions(coordinator);

        sessions[sessionId] = sessions[sessionId] with
        {
            AttachmentState = SessionAttachmentState.DetachedGracePeriod,
            AttachedClientConnectionId = null,
            LeaseExpiresAtUtc = null
        };

        var result = await coordinator.ReattachSessionAsync(
            "user-1",
            new ReattachSessionRequest(sessionId),
            "client-2",
            new DateTimeOffset(2025, 1, 1, 12, 4, 0, TimeSpan.Zero),
            CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.ErrorCode.Should().Be("session-detached-without-lease");
        coordinator.TryGetSession(sessionId, out var corruptedSession).Should().BeTrue();
        corruptedSession.AttachmentState.Should().Be(SessionAttachmentState.Expired);
        corruptedSession.LeaseExpiresAtUtc.Should().BeNull();
    }

    private static InMemorySessionCoordinator CreateCoordinator()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        return new InMemorySessionCoordinator(workers);
    }

    private static ConcurrentDictionary<string, SessionRecord> GetSessions(InMemorySessionCoordinator coordinator)
        => (ConcurrentDictionary<string, SessionRecord>)typeof(InMemorySessionCoordinator)
            .GetField("_sessions", BindingFlags.Instance | BindingFlags.NonPublic)!
            .GetValue(coordinator)!;
}
