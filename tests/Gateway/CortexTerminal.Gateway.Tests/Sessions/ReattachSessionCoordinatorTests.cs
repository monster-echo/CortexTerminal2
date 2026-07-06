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
        var createResult = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
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
        reattachedSession.ReplayPending.Should().BeTrue();
    }

    [Fact]
    public async Task ReattachSessionAsync_WhenAlreadyAttached_ReassignsSessionToNewClient()
    {
        var coordinator = CreateCoordinator();
        var createResult = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: "client-1", CancellationToken.None);
        var nowUtc = new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero);

        var result = await coordinator.ReattachSessionAsync(
            "user-1",
            new ReattachSessionRequest(createResult.Response!.SessionId),
            "client-2",
            nowUtc,
            CancellationToken.None);

        result.Should().BeEquivalentTo(ReattachSessionResult.Success());
        coordinator.TryGetSession(createResult.Response.SessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Attached);
        session.AttachedClientConnectionId.Should().Be("client-2");
        session.ReplayPending.Should().BeTrue();
        session.LastActivityAtUtc.Should().Be(nowUtc);
    }

    [Fact]
    public async Task ReattachSessionAsync_WhenSessionNeedsConsoleEntryWithoutAttachedClient_ReturnsSuccess()
    {
        var coordinator = CreateCoordinator();
        var createResult = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);

        var result = await coordinator.ReattachSessionAsync(
            "user-1",
            new ReattachSessionRequest(createResult.Response!.SessionId),
            "client-2",
            new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero),
            CancellationToken.None);

        result.Should().BeEquivalentTo(ReattachSessionResult.Success());
        coordinator.TryGetSession(createResult.Response.SessionId, out var enteredSession).Should().BeTrue();
        enteredSession.AttachmentState.Should().Be(SessionAttachmentState.Attached);
        enteredSession.AttachedClientConnectionId.Should().Be("client-2");
        enteredSession.ReplayPending.Should().BeTrue();
    }

    [Fact]
    public async Task ReattachSessionAsync_WhenSessionBelongsToDifferentUser_ReturnsSessionNotFound()
    {
        var coordinator = CreateCoordinator();
        var createResult = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);

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
    public async Task ReattachSessionAsync_AfterVeryLongDetach_ForSameUser_ReturnsSuccess()
    {
        // Codifies the product requirement: a DetachedGracePeriod session is reattachable for
        // as long as the worker shell is alive, however long the client was gone. (This is the
        // sess_455 regression — previously a 5-minute lease rejected the reattach.)
        var coordinator = CreateCoordinator();
        var createResult = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var detachedAtUtc = new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero);

        await coordinator.DetachSessionAsync("user-1", sessionId, detachedAtUtc, CancellationToken.None);

        var result = await coordinator.ReattachSessionAsync(
            "user-1",
            new ReattachSessionRequest(sessionId),
            "client-2",
            detachedAtUtc.AddDays(30),
            CancellationToken.None);

        result.Should().BeEquivalentTo(ReattachSessionResult.Success());
        coordinator.TryGetSession(sessionId, out var reattached).Should().BeTrue();
        reattached.AttachmentState.Should().Be(SessionAttachmentState.Attached);
        reattached.AttachedClientConnectionId.Should().Be("client-2");
        reattached.ReplayPending.Should().BeTrue();
    }

    [Fact]
    public async Task ReattachSessionAsync_WhenSessionAlreadyExpired_ReturnsExpired()
    {
        // Terminal states (Expired/Exited) are still rejected — only DetachedGracePeriod
        // recovers unconditionally. Guards the retained rejection branch.
        var coordinator = CreateCoordinator();
        var createResult = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var sessionId = createResult.Response!.SessionId;
        var sessions = GetSessions(coordinator);
        sessions[sessionId] = sessions[sessionId] with { AttachmentState = SessionAttachmentState.Expired };

        var result = await coordinator.ReattachSessionAsync(
            "user-1",
            new ReattachSessionRequest(sessionId),
            "client-2",
            new DateTimeOffset(2025, 1, 1, 12, 0, 0, TimeSpan.Zero),
            CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.ErrorCode.Should().Be("session-expired");
    }

    private static ISessionCoordinator CreateCoordinator()
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        return TestSessionFactory.CreateCoordinator(workers);
    }

    private static ConcurrentDictionary<string, SessionRecord> GetSessions(ISessionCoordinator coordinator)
        => (ConcurrentDictionary<string, SessionRecord>)coordinator.GetType()
            .GetField("_sessions", BindingFlags.Instance | BindingFlags.NonPublic)!
            .GetValue(coordinator)!;
}
