using MessagePack;

namespace CortexTerminal.Contracts.Streaming;

[MessagePackObject]
public sealed record WriteInputFrame(
    [property: Key(0)] string SessionId,
    [property: Key(1)] byte[] Payload);

[MessagePackObject]
public sealed record TerminalChunk(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string Stream,
    [property: Key(2)] byte[] Payload);

[MessagePackObject]
public sealed record SessionStarted(
    [property: Key(0)] string SessionId,
    [property: Key(1)] int Columns,
    [property: Key(2)] int Rows);

[MessagePackObject]
public sealed record SessionExited(
    [property: Key(0)] string SessionId,
    [property: Key(1)] int ExitCode,
    [property: Key(2)] string Reason);

[MessagePackObject]
public sealed record WorkerUnavailableEvent(
    [property: Key(0)] string RequestId,
    [property: Key(1)] string Reason);

[MessagePackObject]
public sealed record AuthExpiredEvent(
    [property: Key(0)] string RequestId);

[MessagePackObject]
public sealed record SessionStartFailedEvent(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string Reason);
