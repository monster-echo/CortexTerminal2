namespace CortexTerminal.Gateway.Sessions;

public sealed record SessionRecord(
    string SessionId,
    string UserId,
    string WorkerId,
    string WorkerConnectionId,
    int Columns,
    int Rows,
    SessionAttachmentState AttachmentState = SessionAttachmentState.Attached,
    string? AttachedClientConnectionId = null,
    DateTimeOffset? LeaseExpiresAtUtc = null);
