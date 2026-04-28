namespace CortexTerminal.Gateway.Audit;

public sealed record AuditLogEntry(
    string Id,
    DateTimeOffset Timestamp,
    string UserId,
    string UserName,
    string Action,
    string TargetEntity,
    string TargetId
);
