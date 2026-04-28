namespace CortexTerminal.Gateway.Workers;

public interface IWorkerRegistry
{
    void Register(string workerId, string connectionId, string? ownerUserId = null);
    void Unregister(string workerId);
    bool TryGetLeastBusy(out RegisteredWorker worker);
    bool TryGetLeastBusyForUser(string userId, out RegisteredWorker worker);
    bool TryGetWorker(string workerId, out RegisteredWorker worker);
    RegisteredWorker? FindByConnectionId(string connectionId);
    IReadOnlyList<RegisteredWorker> GetWorkersForUser(string userId);
    bool SetWorkerOwner(string workerId, string ownerUserId);
}

public sealed record RegisteredWorker(string WorkerId, string ConnectionId, string? OwnerUserId = null, DateTimeOffset? LastSeenAtUtc = null);
