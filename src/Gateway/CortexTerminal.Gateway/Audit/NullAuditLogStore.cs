namespace CortexTerminal.Gateway.Audit;

public sealed class NullAuditLogStore : IAuditLogStore
{
    public void Record(AuditLogEntry entry) { }

    public (IReadOnlyList<AuditLogEntry> Entries, int TotalCount) Query(
        int? page, int? pageSize, string? actionType,
        string? userId, DateTimeOffset? fromDate, DateTimeOffset? toDate)
        => (Array.Empty<AuditLogEntry>(), 0);
}
