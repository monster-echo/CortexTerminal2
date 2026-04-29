using System.Collections.Concurrent;
using CortexTerminal.Gateway.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace CortexTerminal.Gateway.Workers;

public sealed class PostgresWorkerRegistry : IWorkerRegistry
{
    private readonly ConcurrentDictionary<string, RegisteredWorker> _workers = new();
    private readonly IServiceScopeFactory _scopeFactory;

    public PostgresWorkerRegistry(IServiceScopeFactory scopeFactory)
    {
        _scopeFactory = scopeFactory;
    }

    public void Register(string workerId, string connectionId, string? ownerUserId = null)
    {
        var now = DateTimeOffset.UtcNow;
        _workers[workerId] = new RegisteredWorker(workerId, connectionId, ownerUserId, now);

        _ = PersistAsync(async db =>
        {
            var existing = await db.Workers.FindAsync(workerId);
            if (existing is not null)
            {
                existing.IsOnline = true;
                existing.LastSeenAtUtc = now;
                existing.OwnerUserId = ownerUserId;
            }
            else
            {
                db.Workers.Add(new WorkerRecord
                {
                    WorkerId = workerId,
                    OwnerUserId = ownerUserId,
                    LastSeenAtUtc = now,
                    FirstConnectedAtUtc = now,
                    IsOnline = true
                });
            }
        });
    }

    public void Unregister(string workerId)
    {
        _workers.TryRemove(workerId, out _);

        _ = PersistAsync(async db =>
        {
            var existing = await db.Workers.FindAsync(workerId);
            if (existing is not null)
            {
                existing.IsOnline = false;
                existing.LastSeenAtUtc = DateTimeOffset.UtcNow;
            }
        });
    }

    public bool TryGetLeastBusy(out RegisteredWorker worker)
    {
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
        => _workers.Values.Where(w => w.OwnerUserId == userId).ToArray();

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
                _ = PersistAsync(async db =>
                {
                    var record = await db.Workers.FindAsync(workerId);
                    if (record is not null)
                    {
                        record.OwnerUserId = ownerUserId;
                        record.LastSeenAtUtc = DateTimeOffset.UtcNow;
                    }
                });
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
                _ = PersistAsync(async db =>
                {
                    var record = await db.Workers.FindAsync(workerId);
                    if (record is not null)
                    {
                        record.Hostname = metadata?.Hostname;
                        record.OperatingSystem = metadata?.OperatingSystem;
                        record.Architecture = metadata?.Architecture;
                        record.Name = metadata?.Name;
                        record.LastSeenAtUtc = DateTimeOffset.UtcNow;
                    }
                });
                return;
            }
        }
    }

    public IReadOnlyList<RegisteredWorker> GetOnlineWorkersForUser(string userId)
        => _workers.Values
            .Where(w => w.OwnerUserId is null || w.OwnerUserId == userId)
            .ToArray();

    private async Task PersistAsync(Func<AppDbContext, Task> action)
    {
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            await action(db);
            await db.SaveChangesAsync();
        }
        catch
        {
            // DB persistence failure should not block real-time operations
        }
    }
}
