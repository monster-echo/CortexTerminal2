using CortexTerminal.Gateway.Audit;

namespace CortexTerminal.Gateway.Tests.Sessions.Fakes;

internal sealed class RecordingAuditLogStore : IAuditLogStore
{
    public List<AuditLogEntry> Entries { get; } = new();

    public void Record(AuditLogEntry entry) => Entries.Add(entry);

    public (IReadOnlyList<AuditLogEntry> Entries, int TotalCount) Query(
        int? page, int? pageSize, string? actionType,
        string? userId, DateTimeOffset? fromDate, DateTimeOffset? toDate)
        => (Entries, Entries.Count);
}
