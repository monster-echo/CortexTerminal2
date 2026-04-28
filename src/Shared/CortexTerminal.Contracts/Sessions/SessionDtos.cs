using MessagePack;

namespace CortexTerminal.Contracts.Sessions;

[MessagePackObject]
public sealed record CreateSessionRequest(
    [property: Key(0)] string Runtime,
    [property: Key(1)] int Columns,
    [property: Key(2)] int Rows,
    [property: Key(3)] string? ClientRequestId = null);

[MessagePackObject]
public sealed record CreateSessionResponse(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string WorkerId);

[MessagePackObject]
public sealed record ResizePtyRequest(
    [property: Key(0)] string SessionId,
    [property: Key(1)] int Columns,
    [property: Key(2)] int Rows);

[MessagePackObject]
public sealed record CloseSessionRequest(
    [property: Key(0)] string SessionId);

[MessagePackObject]
public sealed record ReattachSessionRequest(
    [property: Key(0)] string SessionId);

[MessagePackObject]
public sealed record ReattachSessionResult(
    [property: Key(0)] bool IsSuccess,
    [property: Key(1)] string? ErrorCode)
{
    public static ReattachSessionResult Success() => new(true, null);

    public static ReattachSessionResult Failure(string errorCode) => new(false, errorCode);
}

[MessagePackObject]
public sealed record CreateSessionResult(
    [property: Key(0)] bool IsSuccess,
    [property: Key(1)] CreateSessionResponse? Response,
    [property: Key(2)] string? ErrorCode)
{
    public static CreateSessionResult Success(CreateSessionResponse response) => new(true, response, null);

    public static CreateSessionResult Failure(string errorCode) => new(false, null, errorCode);
}
