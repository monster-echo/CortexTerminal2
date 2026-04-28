using Microsoft.Extensions.Logging;

namespace CortexTerminal.Gateway.Audit;

public sealed class InMemoryAuditLogStore : IAuditLogStore
{
    private const int MaxEntries = 10_000;
    private readonly List<AuditLogEntry> _entries = [];
    private readonly object _lock = new();

    public void Record(AuditLogEntry entry)
    {
        lock (_lock)
        {
            _entries.Add(entry);
            if (_entries.Count > MaxEntries)
            {
                _entries.RemoveRange(0, _entries.Count - MaxEntries);
            }
        }
    }

    public (IReadOnlyList<AuditLogEntry> Entries, int TotalCount) Query(
        int? page, int? pageSize, string? actionType,
        string? userId, DateTimeOffset? fromDate, DateTimeOffset? toDate)
    {
        List<AuditLogEntry> snapshot;
        lock (_lock)
        {
            snapshot = [.. _entries];
        }

        var filtered = snapshot.AsEnumerable();

        if (!string.IsNullOrEmpty(actionType))
        {
            filtered = filtered.Where(e =>
                e.Action.Equals(actionType, StringComparison.OrdinalIgnoreCase));
        }

        if (!string.IsNullOrEmpty(userId))
        {
            filtered = filtered.Where(e =>
                e.UserId.Equals(userId, StringComparison.OrdinalIgnoreCase));
        }

        if (fromDate.HasValue)
        {
            filtered = filtered.Where(e => e.Timestamp >= fromDate.Value);
        }

        if (toDate.HasValue)
        {
            filtered = filtered.Where(e => e.Timestamp <= toDate.Value);
        }

        var ordered = filtered.OrderByDescending(e => e.Timestamp).ToList();
        var totalCount = ordered.Count;

        var currentPage = page ?? 1;
        var currentPageSize = pageSize ?? 20;
        var paged = ordered
            .Skip((currentPage - 1) * currentPageSize)
            .Take(currentPageSize)
            .ToList();

        return (paged, totalCount);
    }
}
