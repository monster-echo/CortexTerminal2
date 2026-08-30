namespace CortexTerminal.Gateway.Storage;

/// <summary>
/// S3-compatible object storage connection settings. Bound from the "Storage" section —
/// the same key the retired artifact storage used, so production environment injection
/// keeps working unchanged across the RemoteFiles migration.
/// </summary>
public sealed class ObjectStorageOptions
{
    public const string SectionName = "Storage";

    public string Endpoint { get; set; } = string.Empty;

    public string Bucket { get; set; } = string.Empty;

    public string Region { get; set; } = "us-east-1";

    public string AccessKey { get; set; } = string.Empty;

    public string SecretKey { get; set; } = string.Empty;

    public bool ForcePathStyle { get; set; } = true;

    public TimeSpan PresignedUrlTtl { get; set; } = TimeSpan.FromMinutes(15);
}
