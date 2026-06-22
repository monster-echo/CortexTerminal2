using System.Collections.Concurrent;
using CortexTerminal.Gateway.Data;
using Microsoft.EntityFrameworkCore;

namespace CortexTerminal.Gateway.Workers;

public sealed class PostgresWorkerRegistry : IWorkerRegistry
{
    private readonly ConcurrentDictionary<string, RegisteredWorker> _workers = new();
    private readonly IDbContextFactory<AppDbContext> _contextFactory;
    private readonly ILogger<PostgresWorkerRegistry> _logger;

    public PostgresWorkerRegistry(IDbContextFactory<AppDbContext> contextFactory, ILogger<PostgresWorkerRegistry> logger)
    {
        _contextFactory = contextFactory;
        _logger = logger;
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
        }, $"Register:{workerId}");
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
        }, $"Unregister:{workerId}");
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
                }, $"SetWorkerOwner:{workerId}");
                return true;
            }
        }

        return false;
    }

    public void PersistMetadata(string workerId, WorkerMetadata? metadata)
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
                record.Version = metadata?.Version;
                record.LastSeenAtUtc = DateTimeOffset.UtcNow;
            }
        }, $"PersistMetadata:{workerId}");
    }

    public IReadOnlyList<RegisteredWorker> GetOnlineWorkersForUser(string userId)
        => _workers.Values
            .Where(w => w.OwnerUserId is null || w.OwnerUserId == userId)
            .ToArray();

    public async Task<IReadOnlyList<WorkerRecord>> GetAllWorkersForUserAsync(string userId)
    {
        await using var db = await _contextFactory.CreateDbContextAsync();
        return await db.Workers
            .Where(w => w.OwnerUserId == userId)
            .OrderByDescending(w => w.IsOnline)
            .ThenBy(w => w.WorkerId)
            .ToListAsync();
    }

    public int GetOnlineCount() => _workers.Count;

    public IReadOnlyList<RegisteredWorker> GetAllOnline() => _workers.Values.ToArray();

    private async Task PersistAsync(Func<AppDbContext, Task> action, string operation)
    {
        try
        {
            await using var db = await _contextFactory.CreateDbContextAsync();
            await action(db);
            await db.SaveChangesAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "worker.persistence-failed {Operation}", operation);
        }
    }
}
