using MessagePack;

namespace CortexTerminal.Contracts.Sessions;

[MessagePackObject]
public sealed record ArtifactInfo(
    [property: Key(0)] string Id,
    [property: Key(1)] string SessionId,
    [property: Key(2)] string Filename,
    [property: Key(3)] long SizeBytes,
    [property: Key(4)] string Status,
    [property: Key(5)] string Origin,
    [property: Key(6)] string FileCategory,
    [property: Key(7)] DateTimeOffset UploadedAt,
    [property: Key(8)] DateTimeOffset ExpiresAt);

[MessagePackObject]
public sealed record CreateArtifactRequest(
    [property: Key(0)] string SessionId,
    [property: Key(1)] string Filename,
    [property: Key(2)] long SizeBytes,
    [property: Key(3)] string? ContentSha256 = null,
    [property: Key(4)] string Origin = "console");

[MessagePackObject]
public sealed record UploadUrlResponse(
    [property: Key(0)] string ArtifactId,
    [property: Key(1)] string UploadUrl,
    [property: Key(2)] string S3Key,
    [property: Key(3)] DateTimeOffset ExpiresAt);

[MessagePackObject]
public sealed record DownloadUrlResponse(
    [property: Key(0)] string DownloadUrl,
    [property: Key(1)] DateTimeOffset ExpiresAt);

[MessagePackObject]
public sealed record CompleteArtifactRequest(
    [property: Key(0)] string ArtifactId,
    [property: Key(1)] string ContentSha256);

[MessagePackObject]
public sealed record CompleteArtifactAck(
    [property: Key(0)] bool Success,
    [property: Key(1)] string? Error);

public static class ArtifactStatus
{
    public const string Pending = "pending";
    public const string Ready = "ready";
    public const string Deleted = "deleted";
}

public static class ArtifactOrigin
{
    public const string Console = "console";
    public const string Worker = "worker";
}

public static class ArtifactFileCategory
{
    public const string Image = "image";
    public const string Pdf = "pdf";
    public const string Video = "video";
    public const string Audio = "audio";
    public const string Archive = "archive";
    public const string Code = "code";
    public const string Text = "text";
    public const string Unknown = "unknown";
}
