using System.Collections.Concurrent;

namespace CortexTerminal.Gateway.Workers;

public sealed class InMemoryWorkerRegistry : IWorkerRegistry
{
    private readonly ConcurrentDictionary<string, RegisteredWorker> _workers = new();

    public void Register(string workerId, string connectionId, string? ownerUserId = null)
        => _workers[workerId] = new RegisteredWorker(workerId, connectionId, ownerUserId, DateTimeOffset.UtcNow);

    public void Unregister(string workerId)
        => _workers.TryRemove(workerId, out _);

    public bool TryGetLeastBusy(out RegisteredWorker worker)
    {
        // Phase 1: single-session, just pick any available worker
        foreach (var kvp in _workers)
        {
            worker = kvp.Value;
            return true;
        }
        worker = default!;
        return false;
    }

    public bool TryGetLeastBusyForUser(string userId, out RegisteredWorker worker)
    {
        foreach (var kvp in _workers)
        {
            if (kvp.Value.OwnerUserId is null || kvp.Value.OwnerUserId == userId)
            {
                worker = kvp.Value;
                return true;
            }
        }

        worker = default!;
        return false;
    }

    public bool TryGetWorker(string workerId, out RegisteredWorker worker)
        => _workers.TryGetValue(workerId, out worker!);

    public IReadOnlyList<RegisteredWorker> GetWorkersForUser(string userId)
        => _workers.Values.Where(worker => worker.OwnerUserId == userId).ToArray();

    public void SetWorkerOwner(string workerId, string ownerUserId)
    {
        if (!_workers.TryGetValue(workerId, out var existing))
        {
            return;
        }

        if (existing.OwnerUserId is null || existing.OwnerUserId == ownerUserId)
        {
            _workers[workerId] = existing with { OwnerUserId = ownerUserId, LastSeenAtUtc = DateTimeOffset.UtcNow };
        }
    }
}
