using MessagePack;

namespace CortexTerminal.Contracts.Streaming;

[MessagePackObject]
public sealed record SessionDiagnosticReport(
    [property: Key(0)] string State,
    [property: Key(1)] bool HasOutput,
    [property: Key(2)] string? Directory,
    [property: Key(3)] string DirectoryAccess,
    [property: Key(4)] string? Detail,
    [property: Key(5)] string Platform,
    [property: Key(6)] long WaitingSeconds);
