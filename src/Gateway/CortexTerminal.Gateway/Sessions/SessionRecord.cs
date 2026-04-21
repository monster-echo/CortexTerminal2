namespace CortexTerminal.Gateway.Sessions;

public sealed record SessionRecord(
    string SessionId,
    string UserId,
    string WorkerId,
    string WorkerConnectionId,
    int Columns,
    int Rows,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset LastActivityAtUtc,
    SessionAttachmentState AttachmentState = SessionAttachmentState.Attached,
    string? AttachedClientConnectionId = null,
    DateTimeOffset? LeaseExpiresAtUtc = null,
    int? ExitCode = null,
    string? ExitReason = null,
    bool ReplayPending = false);
