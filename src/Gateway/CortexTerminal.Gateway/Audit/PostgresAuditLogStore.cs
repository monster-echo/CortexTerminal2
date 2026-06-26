using CortexTerminal.Gateway.Data;
using Microsoft.EntityFrameworkCore;

namespace CortexTerminal.Gateway.Audit;

public sealed class PostgresAuditLogStore : IAuditLogStore
{
    private readonly IDbContextFactory<AppDbContext> _contextFactory;

    public PostgresAuditLogStore(IDbContextFactory<AppDbContext> contextFactory)
    {
        _contextFactory = contextFactory;
    }

    public void Record(AuditLogEntry entry)
    {
        _ = RecordAsync(entry);
    }

    private async Task RecordAsync(AuditLogEntry entry)
    {
        await using var db = await _contextFactory.CreateDbContextAsync();
        db.AuditLogs.Add(new Data.AuditLog
        {
            Id = entry.Id,
            Timestamp = entry.Timestamp,
            UserId = entry.UserId,
            UserName = entry.UserName,
            Action = entry.Action,
            TargetEntity = entry.TargetEntity,
            TargetId = entry.TargetId,
            ClientIp = entry.ClientIp,
            UserAgent = entry.UserAgent,
            DeviceModel = entry.DeviceModel
        });
        await db.SaveChangesAsync();
    }

    public async Task<(IReadOnlyList<AuditLogEntry> Entries, int TotalCount)> QueryAsync(
        int? page, int? pageSize, string? actionType,
        string? userId, DateTimeOffset? fromDate, DateTimeOffset? toDate)
    {
        await using var db = await _contextFactory.CreateDbContextAsync();

        var query = db.AuditLogs.AsQueryable();

        if (!string.IsNullOrEmpty(actionType))
            query = query.Where(e => e.Action == actionType);

        if (!string.IsNullOrEmpty(userId))
            query = query.Where(e => e.UserId == userId);

        if (fromDate.HasValue)
            query = query.Where(e => e.Timestamp >= fromDate.Value);

        if (toDate.HasValue)
            query = query.Where(e => e.Timestamp <= toDate.Value);

        var totalCount = await query.CountAsync();

        var currentPage = page ?? 1;
        var currentPageSize = pageSize ?? 20;

        var entries = await query
            .OrderByDescending(e => e.Timestamp)
            .Skip((currentPage - 1) * currentPageSize)
            .Take(currentPageSize)
            .Select(e => new AuditLogEntry(
                e.Id, e.Timestamp, e.UserId, e.UserName, e.Action, e.TargetEntity, e.TargetId,
                e.ClientIp, e.UserAgent, e.DeviceModel))
            .ToListAsync();

        return (entries, totalCount);
    }

    public (IReadOnlyList<AuditLogEntry> Entries, int TotalCount) Query(
        int? page, int? pageSize, string? actionType,
        string? userId, DateTimeOffset? fromDate, DateTimeOffset? toDate)
    {
        return QueryAsync(page, pageSize, actionType, userId, fromDate, toDate).GetAwaiter().GetResult();
    }
}
