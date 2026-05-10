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
        coordinator.MarkSessionExited(exited.Response!.SessionId, 0, "completed");

        var reboundCount = coordinator.RebindActiveSessions("user-1", "worker-1", "worker-conn-2");

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
        coordinator.MarkSessionExited(createResult.Response!.SessionId, 0, "completed");

        var result = await coordinator.DeleteSessionAsync("user-1", createResult.Response.SessionId, CancellationToken.None);

        result.Should().Be(DeleteSessionResult.Success());
        coordinator.TryGetSession(createResult.Response.SessionId, out _).Should().BeFalse();
    }

    [Fact]
    public async Task DeleteSessionAsync_WhenSessionIsStillRunning_ReturnsFailure()
    {
        var coordinator = CreateCoordinator();
        var createResult = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), "client-1", CancellationToken.None);
        await coordinator.DetachSessionAsync("user-1", createResult.Response!.SessionId, DateTimeOffset.UtcNow, CancellationToken.None);

        var result = await coordinator.DeleteSessionAsync("user-1", createResult.Response.SessionId, CancellationToken.None);

        result.Should().Be(DeleteSessionResult.Failure("session-running"));
        coordinator.TryGetSession(createResult.Response.SessionId, out _).Should().BeTrue();
    }

    private static InMemorySessionCoordinator CreateCoordinator()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        return new InMemorySessionCoordinator(workers);
    }
}
