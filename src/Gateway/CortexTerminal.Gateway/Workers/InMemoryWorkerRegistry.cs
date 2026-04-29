using System.Collections.Concurrent;
using CortexTerminal.Gateway.Data;

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

    public RegisteredWorker? FindByConnectionId(string connectionId)
        => _workers.Values.FirstOrDefault(w => w.ConnectionId == connectionId);

    public IReadOnlyList<RegisteredWorker> GetWorkersForUser(string userId)
        => _workers.Values.Where(worker => worker.OwnerUserId == userId).ToArray();

    public bool SetWorkerOwner(string workerId, string ownerUserId)
    {
        while (_workers.TryGetValue(workerId, out var existing))
        {
            if (existing.OwnerUserId is not null && existing.OwnerUserId != ownerUserId)
            {
                return false;
            }

            var updated = existing with { OwnerUserId = ownerUserId, LastSeenAtUtc = DateTimeOffset.UtcNow };
            if (_workers.TryUpdate(workerId, updated, existing))
            {
                return true;
            }
        }

        return false;
    }

    public void UpdateMetadata(string workerId, WorkerMetadata? metadata)
    {
        while (_workers.TryGetValue(workerId, out var existing))
        {
            var updated = existing with { Metadata = metadata, LastSeenAtUtc = DateTimeOffset.UtcNow };
            if (_workers.TryUpdate(workerId, updated, existing))
            {
                return;
            }
        }
    }

    public IReadOnlyList<RegisteredWorker> GetOnlineWorkersForUser(string userId)
        => _workers.Values
            .Where(w => w.OwnerUserId is null || w.OwnerUserId == userId)
            .ToArray();

    public Task<IReadOnlyList<WorkerRecord>> GetAllWorkersForUserAsync(string userId)
    {
        var records = _workers.Values
            .Where(w => w.OwnerUserId == userId)
            .Select(w => new WorkerRecord
            {
                WorkerId = w.WorkerId,
                OwnerUserId = w.OwnerUserId,
                Hostname = w.Metadata?.Hostname,
                OperatingSystem = w.Metadata?.OperatingSystem,
                Architecture = w.Metadata?.Architecture,
                Name = w.Metadata?.Name,
                Version = w.Metadata?.Version,
                LastSeenAtUtc = w.LastSeenAtUtc ?? DateTimeOffset.UtcNow,
                FirstConnectedAtUtc = w.LastSeenAtUtc,
                IsOnline = true
            })
            .ToList();

        return Task.FromResult<IReadOnlyList<WorkerRecord>>(records);
    }
}
