using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Data;
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

        var result = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.ErrorCode.Should().Be("no-worker-available");
    }

    [Fact]
    public async Task CreateSessionAsync_WithRegisteredWorker_ReturnsSuccess()
    {
        var workers = new InMemoryWorkerRegistry();
        workers.Register("worker-1", "conn-1");
        var coordinator = new InMemorySessionCoordinator(workers);

        var result = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);

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

        var result = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var found = coordinator.TryGetSession(result.Response!.SessionId, out var session);

        found.Should().BeTrue();
        session.UserId.Should().Be("user-1");
        session.WorkerId.Should().Be("worker-1");
        session.Columns.Should().Be(120);
        session.Rows.Should().Be(40);
    }

    [Fact]
    public async Task CreateSessionAsync_WhenWorkerOwnershipClaimFails_ReturnsWorkerUnavailable()
    {
        var workers = new ClaimFailingWorkerRegistry();
        var coordinator = new InMemorySessionCoordinator(workers);

        var result = await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.ErrorCode.Should().Be("no-worker-available");
        coordinator.GetSessionsForUser("user-1").Should().BeEmpty();
    }

    [Fact]
    public async Task CreateSessionAsync_WhenOwnershipClaimLosesRace_ReturnsWorkerUnavailable()
    {
        var workers = new CoordinatedWorkerRegistry();
        workers.Register("worker-1", "conn-1");
        var coordinator = new InMemorySessionCoordinator(workers);

        var userA = Task.Run(() => coordinator.CreateSessionAsync("user-a", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None));
        var userB = Task.Run(() => coordinator.CreateSessionAsync("user-b", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None));

        var results = await Task.WhenAll(userA, userB);

        results.Count(result => result.IsSuccess).Should().Be(1);
        results.Count(result => !result.IsSuccess && result.ErrorCode == "no-worker-available").Should().Be(1);

        var successfulUser = results[0].IsSuccess ? "user-a" : "user-b";
        var failedUser = successfulUser == "user-a" ? "user-b" : "user-a";

        coordinator.GetSessionsForUser(successfulUser).Should().ContainSingle();
        coordinator.GetSessionsForUser(failedUser).Should().BeEmpty();
        workers.TryGetWorker("worker-1", out var worker).Should().BeTrue();
        worker.OwnerUserId.Should().Be(successfulUser);
    }

    private sealed class ClaimFailingWorkerRegistry : IWorkerRegistry
    {
        private readonly RegisteredWorker _worker = new("worker-1", "conn-1");

        public void Register(string workerId, string connectionId, string? ownerUserId = null)
            => throw new NotSupportedException();

        public void Unregister(string workerId)
            => throw new NotSupportedException();

        public bool TryGetLeastBusy(out RegisteredWorker worker)
        {
            worker = _worker;
            return true;
        }

        public bool TryGetLeastBusyForUser(string userId, out RegisteredWorker worker)
        {
            worker = _worker;
            return true;
        }

        public bool TryGetWorker(string workerId, out RegisteredWorker worker)
        {
            worker = _worker;
            return workerId == _worker.WorkerId;
        }

        public RegisteredWorker? FindByConnectionId(string connectionId)
            => _worker.ConnectionId == connectionId ? _worker : null;

        public IReadOnlyList<RegisteredWorker> GetWorkersForUser(string userId)
            => Array.Empty<RegisteredWorker>();

        public bool SetWorkerOwner(string workerId, string ownerUserId)
        {
            return false;
        }

        public void UpdateMetadata(string workerId, WorkerMetadata? metadata)
            => throw new NotSupportedException();

        public IReadOnlyList<RegisteredWorker> GetOnlineWorkersForUser(string userId)
            => throw new NotSupportedException();

        public Task<IReadOnlyList<WorkerRecord>> GetAllWorkersForUserAsync(string userId)
            => Task.FromResult<IReadOnlyList<WorkerRecord>>(Array.Empty<WorkerRecord>());
    }

    private sealed class CoordinatedWorkerRegistry : IWorkerRegistry
    {
        private readonly InMemoryWorkerRegistry _inner = new();
        private readonly CountdownEvent _selectionBarrier = new(2);

        public void Register(string workerId, string connectionId, string? ownerUserId = null)
            => _inner.Register(workerId, connectionId, ownerUserId);

        public void Unregister(string workerId)
            => _inner.Unregister(workerId);

        public bool TryGetLeastBusy(out RegisteredWorker worker)
            => _inner.TryGetLeastBusy(out worker);

        public bool TryGetLeastBusyForUser(string userId, out RegisteredWorker worker)
        {
            var found = _inner.TryGetLeastBusyForUser(userId, out worker);
            if (!found)
            {
                return false;
            }

            _selectionBarrier.Signal();
            _selectionBarrier.Wait(TimeSpan.FromSeconds(5)).Should().BeTrue("both session creations must observe the same worker before claiming ownership");
            return true;
        }

        public bool TryGetWorker(string workerId, out RegisteredWorker worker)
            => _inner.TryGetWorker(workerId, out worker);

        public RegisteredWorker? FindByConnectionId(string connectionId)
            => _inner.FindByConnectionId(connectionId);

        public IReadOnlyList<RegisteredWorker> GetWorkersForUser(string userId)
            => _inner.GetWorkersForUser(userId);

        public bool SetWorkerOwner(string workerId, string ownerUserId)
            => _inner.SetWorkerOwner(workerId, ownerUserId);

        public void UpdateMetadata(string workerId, WorkerMetadata? metadata)
            => _inner.UpdateMetadata(workerId, metadata);

        public IReadOnlyList<RegisteredWorker> GetOnlineWorkersForUser(string userId)
            => _inner.GetOnlineWorkersForUser(userId);

        public Task<IReadOnlyList<WorkerRecord>> GetAllWorkersForUserAsync(string userId)
            => _inner.GetAllWorkersForUserAsync(userId);
    }
}
