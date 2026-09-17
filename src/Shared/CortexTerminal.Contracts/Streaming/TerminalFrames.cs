using MessagePack;

namespace CortexTerminal.Contracts.Streaming;

[MessagePackObject]
public sealed record WriteInputFrame(
    [property: Key(0)] string SessionId,
    [property: Key(1)] byte[] Payload);

[MessagePackObject]
public sealed record LatencyProbeFrame(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string ProbeId);

[MessagePackObject]
public sealed record StartSessionCommand(
    [property: Key(0)] string SessionId,
    [property: Key(1)] int Columns,
    [property: Key(2)] int Rows,
    [property: Key(3)] int MaxBytes,
    [property: Key(4)] string? Cwd = null);

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

[MessagePackObject]
public sealed record SessionDetachedEvent(
    [property: Key(0)] string SessionId);

// Worker → gateway: the live session ids currently held by a worker process.
// Sent right after RegisterWorker so the gateway can expire any of its sessions
// for this worker that the worker no longer knows about (e.g. after a worker
// restart killed every shell). Lets "worker restart = session ends" hold even
// though the gateway otherwise keeps sessions alive indefinitely.
[MessagePackObject]
public sealed record WorkerSessionsSnapshot(
    [property: Key(0)] string[] LiveSessionIds);

[MessagePackObject]
public sealed record SessionReattachedEvent(
    [property: Key(0)] string SessionId);

[MessagePackObject]
public sealed record SessionExpiredEvent(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string Reason);

[MessagePackObject]
public sealed record ReplayChunk(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string Stream,
    [property: Key(2)] byte[] Payload);

[MessagePackObject]
public sealed record ReplayCompleted(
    [property: Key(0)] string SessionId);

/// <summary>
/// Gateway → worker answer item for an incremental scrollback request: one
/// retained chunk plus its per-session sequence number.
/// </summary>
[MessagePackObject]
public sealed record ScrollbackItem(
    [property: Key(0)] long Seq,
    [property: Key(1)] TerminalChunk Chunk);

/// <summary>
/// Worker → gateway: incremental scrollback answer. Gap=true means the
/// requested cursor predates the retained window (trim or stream restart):
/// Items then hold the FULL retained buffer and the client must reset its
/// screen before applying them. Gap=false → Items are strictly the chunks
/// after the requested cursor and the client continues without a reset.
/// </summary>
[MessagePackObject]
public sealed record ScrollbackDelta(
    [property: Key(0)] bool Gap,
    [property: Key(1)] long LastSeq,
    [property: Key(2)] ScrollbackItem[] Items);

/// <summary>
/// Incremental-replay client events (hub method ReattachSessionIncremental).
/// Entirely new event names: legacy clients never subscribe to them, and
/// legacy full-replay events keep their exact original shapes.
/// </summary>
[MessagePackObject]
public sealed record ReplayDeltaStarted(
    [property: Key(0)] string SessionId);

[MessagePackObject]
public sealed record ReplayDeltaChunk(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string Stream,
    [property: Key(2)] byte[] Payload,
    [property: Key(3)] long Seq);

[MessagePackObject]
public sealed record ReplayDeltaCompleted(
    [property: Key(0)] string SessionId,
    [property: Key(1)] long LastSeq);

[MessagePackObject]
public sealed record SessionDisplacedEvent(
    [property: Key(0)] string SessionId);

[MessagePackObject]
public sealed record WorkerInfoFrame(
    [property: Key(0)] string WorkerId,
    [property: Key(1)] string? Hostname,
    [property: Key(2)] string? OperatingSystem,
    [property: Key(3)] string? Architecture,
    [property: Key(4)] string? MachineName,
    [property: Key(5)] string? Version,
    [property: Key(6)] double? CpuUsagePercent = null,
    [property: Key(7)] double? MemoryUsagePercent = null,
    [property: Key(8)] string? HomePath = null,
    [property: Key(9)] string[]? LanEndpoints = null,
    [property: Key(10)] string? PublicTransferBaseUrl = null);

[MessagePackObject]
public sealed record UpgradeWorkerCommand(
    [property: Key(0)] string TargetVersion,
    [property: Key(1)] string DownloadUrl);
