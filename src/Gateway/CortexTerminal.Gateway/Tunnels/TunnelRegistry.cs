using CortexTerminal.Gateway.Data;
using Microsoft.EntityFrameworkCore;

namespace CortexTerminal.Gateway.Tunnels;

/// <summary>tunnels 表的持久化访问。所有查询自动排除已撤销(软删除)记录。</summary>
public sealed class TunnelRegistry(IDbContextFactory<AppDbContext> dbFactory, TimeProvider timeProvider)
{
    public async Task<TunnelEntity> CreateAsync(
        string tunnelKey, string secretHash, string ownerUserId,
        string workerId, string workerConnectionId, string sessionId,
        int port, TimeSpan ttl,
        string workspaceId = "", string? name = null, int localPort = 0, string remoteAddress = "127.0.0.1")
    {
        var now = timeProvider.GetUtcNow();
        var entity = new TunnelEntity
        {
            Id = Guid.NewGuid().ToString("N"),
            TunnelKey = tunnelKey,
            SecretHash = secretHash,
            OwnerUserId = ownerUserId,
            WorkspaceId = workspaceId,
            Name = name,
            LocalPort = localPort,
            RemoteAddress = remoteAddress,
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

    public async Task<TunnelEntity?> FindOwnedAsync(string tunnelId, string ownerUserId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        return await db.Tunnels.AsNoTracking()
            .FirstOrDefaultAsync(t => t.Id == tunnelId && t.OwnerUserId == ownerUserId && t.RevokedAtUtc == null);
    }

    public async Task<IReadOnlyList<TunnelEntity>> ListForSessionAsync(string sessionId, string ownerUserId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        return await db.Tunnels.AsNoTracking()
            .Where(t => t.SessionId == sessionId && t.OwnerUserId == ownerUserId && t.RevokedAtUtc == null)
            .OrderBy(t => t.CreatedAtUtc)
            .ToListAsync();
    }

    public async Task<IReadOnlyList<TunnelEntity>> ListForWorkspaceAsync(string workspaceId, string ownerUserId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        return await db.Tunnels.AsNoTracking()
            .Where(t => t.WorkspaceId == workspaceId && t.OwnerUserId == ownerUserId && t.RevokedAtUtc == null)
            .OrderBy(t => t.CreatedAtUtc)
            .ToListAsync();
    }

    /// <summary>编辑 workspace 级转发规则字段；null 表示该字段不修改。url/secret/归属不变。</summary>
    public async Task<TunnelEntity?> UpdateAsync(
        string tunnelId, string ownerUserId,
        string? name, int? localPort, string? remoteAddress, int? remotePort,
        string? workerConnectionId = null)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var entity = await db.Tunnels
            .FirstOrDefaultAsync(t => t.Id == tunnelId && t.OwnerUserId == ownerUserId && t.RevokedAtUtc == null);
        if (entity is null) return null;

        // name 传空串表示清除名称。
        if (name is not null)
        {
            var trimmed = name.Trim();
            entity.Name = trimmed.Length == 0 ? null : trimmed;
        }
        if (localPort is not null) entity.LocalPort = localPort.Value;
        if (remoteAddress is not null) entity.RemoteAddress = remoteAddress;
        if (remotePort is not null) entity.Port = remotePort.Value;
        if (workerConnectionId is not null) entity.WorkerConnectionId = workerConnectionId;
        await db.SaveChangesAsync();
        return entity;
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

    public async Task<int> CountActiveForWorkspaceAsync(string workspaceId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        return await db.Tunnels.CountAsync(t => t.WorkspaceId == workspaceId && t.RevokedAtUtc == null);
    }
}
