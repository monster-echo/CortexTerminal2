using CortexTerminal.Gateway.Data;
using Microsoft.EntityFrameworkCore;

namespace CortexTerminal.Gateway.Tunnels;

/// <summary>tunnels 表的持久化访问。所有查询自动排除已撤销(软删除)记录。</summary>
public sealed class TunnelRegistry(IDbContextFactory<AppDbContext> dbFactory, TimeProvider timeProvider)
{
    public async Task<TunnelEntity> CreateAsync(
        string tunnelKey, string secretHash, string ownerUserId,
        string workerId, string workerConnectionId, string sessionId,
        int port, TimeSpan ttl)
    {
        var now = timeProvider.GetUtcNow();
        var entity = new TunnelEntity
        {
            Id = Guid.NewGuid().ToString("N"),
            TunnelKey = tunnelKey,
            SecretHash = secretHash,
            OwnerUserId = ownerUserId,
            WorkerId = workerId,
            WorkerConnectionId = workerConnectionId,
            SessionId = sessionId,
            Port = port,
            TransportType = "http",
            CreatedAtUtc = now,
            ExpiresAtUtc = now + ttl,
        };
        await using var db = await dbFactory.CreateDbContextAsync();
        db.Tunnels.Add(entity);
        await db.SaveChangesAsync();
        return entity;
    }

    public async Task<TunnelEntity?> FindByKeyAsync(string tunnelKey)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        return await db.Tunnels.AsNoTracking()
            .FirstOrDefaultAsync(t => t.TunnelKey == tunnelKey && t.RevokedAtUtc == null);
    }

    public async Task<IReadOnlyList<TunnelEntity>> ListForSessionAsync(string sessionId, string ownerUserId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        return await db.Tunnels.AsNoTracking()
            .Where(t => t.SessionId == sessionId && t.OwnerUserId == ownerUserId && t.RevokedAtUtc == null)
            .OrderBy(t => t.CreatedAtUtc)
            .ToListAsync();
    }

    public async Task<bool> RevokeAsync(string tunnelId, string ownerUserId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var entity = await db.Tunnels.FirstOrDefaultAsync(t => t.Id == tunnelId && t.OwnerUserId == ownerUserId && t.RevokedAtUtc == null);
        if (entity is null) return false;
        entity.RevokedAtUtc = timeProvider.GetUtcNow();
        await db.SaveChangesAsync();
        return true;
    }

    public async Task<int> CountActiveForSessionAsync(string sessionId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        return await db.Tunnels.CountAsync(t => t.SessionId == sessionId && t.RevokedAtUtc == null);
    }
}
