using CortexTerminal.Gateway.Data;
using Microsoft.EntityFrameworkCore;

namespace CortexTerminal.Gateway.Workspaces;

/// <summary>工作区不存在或已删除。</summary>
public sealed class WorkspaceNotFoundException(string message) : Exception(message);

/// <summary>工作区不属于当前用户。</summary>
public sealed class WorkspaceForbiddenException(string message) : Exception(message);

/// <summary>工作区的持久化访问。所有查询自动排除已删除记录；(WorkerId, Name) 唯一。</summary>
public sealed class WorkspaceRegistry(IDbContextFactory<AppDbContext> dbFactory, TimeProvider timeProvider)
{
    public async Task<WorkspaceEntity> GetOwnedAsync(string userId, string workspaceId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var entity = await db.Workspaces.AsNoTracking()
            .FirstOrDefaultAsync(w => w.Id == workspaceId && w.DeletedAtUtc == null);
        if (entity is null)
        {
            throw new WorkspaceNotFoundException("Workspace not found");
        }
        if (entity.OwnerUserId != userId)
        {
            throw new WorkspaceForbiddenException("Workspace belongs to another user");
        }
        return entity;
    }

    public async Task<IReadOnlyList<WorkspaceEntity>> ListForUserAsync(string userId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        return await db.Workspaces.AsNoTracking()
            .Where(w => w.OwnerUserId == userId && w.DeletedAtUtc == null)
            .OrderBy(w => w.WorkerId).ThenBy(w => w.CreatedAtUtc)
            .ToListAsync();
    }

    public async Task<WorkspaceEntity> CreateAsync(string userId, string workerId, string name, string rootPath, bool isDefault = false)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var entity = new WorkspaceEntity
        {
            Id = $"ws_{Guid.NewGuid():N}",
            OwnerUserId = userId,
            WorkerId = workerId,
            Name = name,
            RootPath = rootPath,
            IsDefault = isDefault,
            CreatedAtUtc = timeProvider.GetUtcNow(),
        };
        db.Workspaces.Add(entity);
        await db.SaveChangesAsync();
        return entity;
    }

    /// <summary>Worker 首次上报 home 时幂等创建默认工作区（同 worker 已有任何工作区则跳过）。</summary>
    public async Task EnsureDefaultAsync(string userId, string workerId, string homePath)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var exists = await db.Workspaces.AsNoTracking()
            .AnyAsync(w => w.WorkerId == workerId && w.DeletedAtUtc == null);
        if (exists)
        {
            return;
        }
        db.Workspaces.Add(new WorkspaceEntity
        {
            Id = $"ws_{Guid.NewGuid():N}",
            OwnerUserId = userId,
            WorkerId = workerId,
            Name = "Home",
            RootPath = homePath,
            IsDefault = true,
            CreatedAtUtc = timeProvider.GetUtcNow(),
        });
        await db.SaveChangesAsync();
    }

    /// <summary>软删除。默认工作区与仍有会话绑定的工作区拒绝删除。</summary>
    public async Task DeleteAsync(string userId, string workspaceId, int boundSessionCount)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var entity = await db.Workspaces
            .FirstOrDefaultAsync(w => w.Id == workspaceId && w.OwnerUserId == userId && w.DeletedAtUtc == null)
            ?? throw new WorkspaceNotFoundException("Workspace not found");
        if (entity.IsDefault)
        {
            throw new InvalidOperationException("The default workspace cannot be deleted");
        }
        if (boundSessionCount > 0)
        {
            throw new InvalidOperationException($"Workspace still has {boundSessionCount} bound sessions");
        }
        entity.DeletedAtUtc = timeProvider.GetUtcNow();
        await db.SaveChangesAsync();
    }
}
