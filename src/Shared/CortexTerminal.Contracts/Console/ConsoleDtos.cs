using MessagePack;

namespace CortexTerminal.Contracts.Console;

[MessagePackObject]
public sealed record SessionSummaryDto(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string WorkerId);

[MessagePackObject]
public sealed record WorkerSummaryDto(
    [property: Key(0)] string WorkerId,
    [property: Key(1)] string Name);

[MessagePackObject]
public sealed record WorkerDetailDto(
    [property: Key(0)] string WorkerId,
    [property: Key(1)] string Name,
    [property: Key(2)] string Address);
