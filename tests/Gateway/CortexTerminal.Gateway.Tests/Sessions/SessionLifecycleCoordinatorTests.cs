using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Sessions;

public sealed class SessionLifecycleCoordinatorTests
{
    [Fact]
    public async Task RebindActiveSessions_UpdatesAttachedAndDetachedSessionsOnly()
    {
        var coordinator = CreateCoordinator();
        var attached = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-1", CancellationToken.None);
        var detached = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-2", CancellationToken.None);
        var exited = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-3", CancellationToken.None);
        await coordinator.DetachSessionAsync("user-1", detached.Response!.SessionId, DateTimeOffset.UtcNow, CancellationToken.None);
        await coordinator.MarkSessionExited(exited.Response!.SessionId, 0, "completed");

        var reboundCount = await coordinator.RebindActiveSessions("user-1", "worker-1", "worker-conn-2");

        reboundCount.Should().Be(2);
        coordinator.TryGetSession(attached.Response!.SessionId, out var attachedSession).Should().BeTrue();
        attachedSession.WorkerConnectionId.Should().Be("worker-conn-2");
        coordinator.TryGetSession(detached.Response!.SessionId, out var detachedSession).Should().BeTrue();
        detachedSession.WorkerConnectionId.Should().Be("worker-conn-2");
        coordinator.TryGetSession(exited.Response!.SessionId, out var exitedSession).Should().BeTrue();
        exitedSession.WorkerConnectionId.Should().Be("worker-conn-1");
    }

    [Fact]
    public async Task DeleteSessionAsync_RemovesExitedSession()
    {
        var coordinator = CreateCoordinator();
        var createResult = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-1", CancellationToken.None);
        await coordinator.MarkSessionExited(createResult.Response!.SessionId, 0, "completed");

        var result = await coordinator.DeleteSessionAsync("user-1", createResult.Response.SessionId, CancellationToken.None);

        result.Should().Be(DeleteSessionResult.Success());
        coordinator.TryGetSession(createResult.Response.SessionId, out _).Should().BeFalse();
    }

    [Fact]
    public async Task DeleteSessionAsync_WhenSessionIsStillRunning_SucceedsAndTerminates()
    {
        var coordinator = CreateCoordinator();
        var createResult = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-1", CancellationToken.None);
        await coordinator.DetachSessionAsync("user-1", createResult.Response!.SessionId, DateTimeOffset.UtcNow, CancellationToken.None);

        var result = await coordinator.DeleteSessionAsync("user-1", createResult.Response.SessionId, CancellationToken.None);

        result.Should().Be(DeleteSessionResult.Success());
        coordinator.TryGetSession(createResult.Response.SessionId, out _).Should().BeFalse();
    }

    [Fact]
    public async Task TransitionToRecovering_TransitionsAttachedAndDetachedSessions()
    {
        var coordinator = CreateCoordinator();
        var attached = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-1", CancellationToken.None);
        var detached = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-2", CancellationToken.None);
        await coordinator.DetachSessionAsync("user-1", detached.Response!.SessionId, DateTimeOffset.UtcNow, CancellationToken.None);

        var transitionedSessions = await coordinator.TransitionToRecovering("worker-1", "worker-conn-1");

        transitionedSessions.Should().HaveCount(2);

        coordinator.TryGetSession(attached.Response!.SessionId, out var attachedSession).Should().BeTrue();
        attachedSession.AttachmentState.Should().Be(SessionAttachmentState.Recovering);
        attachedSession.ExitReason.Should().BeNull();
        attachedSession.WorkerConnectionId.Should().BeEmpty();
        attachedSession.AttachedClientConnectionId.Should().BeNull();

        coordinator.TryGetSession(detached.Response!.SessionId, out var detachedSession).Should().BeTrue();
        detachedSession.AttachmentState.Should().Be(SessionAttachmentState.Recovering);
        detachedSession.ExitReason.Should().BeNull();
    }

    [Fact]
    public async Task TransitionToRecovering_ReturnsOriginalRecordsWithClientConnectionIds()
    {
        var coordinator = CreateCoordinator();
        await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-1", CancellationToken.None);

        var transitionedSessions = await coordinator.TransitionToRecovering("worker-1", "worker-conn-1");

        transitionedSessions.Should().ContainSingle();
        transitionedSessions[0].AttachedClientConnectionId.Should().Be("client-1");
    }

    [Fact]
    public async Task TransitionToRecovering_DoesNotTransitionAlreadyExitedSessions()
    {
        var coordinator = CreateCoordinator();
        var exited = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-1", CancellationToken.None);
        await coordinator.MarkSessionExited(exited.Response!.SessionId, 0, "completed");

        var transitionedSessions = await coordinator.TransitionToRecovering("worker-1", "worker-conn-1");

        transitionedSessions.Should().BeEmpty();
        coordinator.TryGetSession(exited.Response!.SessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Exited);
        session.ExitReason.Should().Be("completed");
    }

    [Fact]
    public async Task TransitionToRecovering_DoesNotTransitionSessionsWithDifferentConnectionId()
    {
        var coordinator = CreateCoordinator();
        await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-1", CancellationToken.None);
        // Rebind to a new connection
        await coordinator.RebindActiveSessions("user-1", "worker-1", "worker-conn-2");

        // Disconnect the OLD connection - should NOT transition since session is now on conn-2
        var transitionedSessions = await coordinator.TransitionToRecovering("worker-1", "worker-conn-1");

        transitionedSessions.Should().BeEmpty();
    }

    [Fact]
    public async Task TransitionToRecovering_DoesNotTransitionOtherWorkersSessions()
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        workers.Register("worker-2", "worker-conn-2");
        var coordinator = TestSessionFactory.CreateCoordinator(workers);
        await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-1", CancellationToken.None);

        var transitionedSessions = await coordinator.TransitionToRecovering("worker-2", "worker-conn-2");

        transitionedSessions.Should().BeEmpty();
    }

    [Fact]
    public async Task TransitionToRecovering_FollowedByRebindRestoresSessionsToAttached()
    {
        var coordinator = CreateCoordinator();
        var attached = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-1", CancellationToken.None);

        await coordinator.TransitionToRecovering("worker-1", "worker-conn-1");
        var reboundCount = await coordinator.RebindActiveSessions("user-1", "worker-1", "worker-conn-2");

        reboundCount.Should().Be(1);
        coordinator.TryGetSession(attached.Response!.SessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Attached);
        session.WorkerConnectionId.Should().Be("worker-conn-2");
    }

    [Fact]
    public async Task DeleteSessionAsync_SucceedsForRunningSession()
    {
        var coordinator = CreateCoordinator();
        var result = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-1", CancellationToken.None);

        var deleteResult = await coordinator.DeleteSessionAsync("user-1", result.Response!.SessionId, CancellationToken.None);
        deleteResult.IsSuccess.Should().BeTrue();
    }

    private static ISessionCoordinator CreateCoordinator()
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        return TestSessionFactory.CreateCoordinator(workers);
    }
}
