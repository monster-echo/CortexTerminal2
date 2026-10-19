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

    /// <summary>
    /// 软删除的工作区不占用名字：只检查未删除的行，与数据库的部分唯一索引一致。
    /// </summary>
    public async Task<bool> NameExistsAsync(string workerId, string name)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        return await db.Workspaces.AnyAsync(w => w.WorkerId == workerId && w.Name == name && w.DeletedAtUtc == null);
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

    /// <summary>软删除工作区，并在同一次保存中删除所属会话记录；保留电脑上的文件。</summary>
    public async Task<IReadOnlyList<string>> DeleteAsync(string userId, string workspaceId)
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        var entity = await db.Workspaces
            .FirstOrDefaultAsync(w => w.Id == workspaceId && w.OwnerUserId == userId && w.DeletedAtUtc == null)
            ?? throw new WorkspaceNotFoundException("Workspace not found");
        var boundSessions = await db.Sessions
            .Where(s => s.UserId == userId && s.WorkspaceId == workspaceId)
            .ToListAsync();
        db.Sessions.RemoveRange(boundSessions);
        entity.DeletedAtUtc = timeProvider.GetUtcNow();
        await db.SaveChangesAsync();
        return boundSessions.Select(s => s.SessionId).ToList();
    }
}
