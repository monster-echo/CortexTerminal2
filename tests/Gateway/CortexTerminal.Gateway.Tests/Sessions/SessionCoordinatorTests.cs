using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Sessions;

public sealed class SessionCoordinatorTests
{
    [Fact]
    public async Task CreateSessionAsync_WithoutAnyRegisteredWorker_ReturnsWorkerUnavailable()
    {
        var workers = new InMemoryWorkerRegistry();
        var coordinator = new InMemorySessionCoordinator(workers);

        var result = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.ErrorCode.Should().Be("no-worker-available");
    }

    [Fact]
    public async Task CreateSessionAsync_WithRegisteredWorker_ReturnsSuccess()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "conn-1");
        var coordinator = new InMemorySessionCoordinator(workers);

        var result = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Response.Should().NotBeNull();
        result.Response!.SessionId.Should().StartWith("sess_");
        result.Response.WorkerId.Should().Be("worker-1");
    }

    [Fact]
    public async Task TryGetSession_AfterCreate_ReturnsTrue()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "conn-1");
        var coordinator = new InMemorySessionCoordinator(workers);

        var result = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), CancellationToken.None);
        var found = coordinator.TryGetSession(result.Response!.SessionId, out var session);

        found.Should().BeTrue();
        session.UserId.Should().Be("user-1");
        session.WorkerId.Should().Be("worker-1");
        session.Columns.Should().Be(120);
        session.Rows.Should().Be(40);
    }
}
