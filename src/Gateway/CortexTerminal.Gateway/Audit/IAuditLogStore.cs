namespace CortexTerminal.Gateway.Audit;

public interface IAuditLogStore
{
    void Record(AuditLogEntry entry);
    (IReadOnlyList<AuditLogEntry> Entries, int TotalCount) Query(
        int? page, int? pageSize, string? actionType,
        string? userId, DateTimeOffset? fromDate, DateTimeOffset? toDate);
}
