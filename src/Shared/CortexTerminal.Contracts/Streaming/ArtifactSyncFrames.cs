using CortexTerminal.Contracts.Sessions;
using MessagePack;

namespace CortexTerminal.Contracts.Streaming;

[MessagePackObject]
public sealed record NotifyArtifactUploadedFrame(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string Filename,
    [property: Key(2)] string DownloadUrl,
    [property: Key(3)] long SizeBytes,
    [property: Key(4)] string ContentSha256);

[MessagePackObject]
public sealed record ArtifactSyncedFrame(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string Filename,
    [property: Key(2)] bool Success,
    [property: Key(3)] string? Error);

[MessagePackObject]
public sealed record ReportArtifactDeletedFrame(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string Filename);

[MessagePackObject]
public sealed record ArtifactChangedEvent(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string ArtifactId,
    [property: Key(2)] string ChangeType,
    [property: Key(3)] ArtifactInfo? Artifact);

public static class ArtifactChangeType
{
    public const string Created = "created";
    public const string Updated = "updated";
    public const string Deleted = "deleted";
}
