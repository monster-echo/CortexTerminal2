namespace CortexTerminal.Gateway.Storage;

public sealed class ArtifactStorageOptions
{
    public const string SectionName = "Storage";

    public string Endpoint { get; set; } = string.Empty;

    public string Bucket { get; set; } = string.Empty;

    public string Region { get; set; } = "us-east-1";

    public string AccessKey { get; set; } = string.Empty;

    public string SecretKey { get; set; } = string.Empty;

    public bool ForcePathStyle { get; set; } = true;

    public TimeSpan PresignedUrlTtl { get; set; } = TimeSpan.FromMinutes(15);

    public long MaxArtifactSizeBytes { get; set; } = 50 * 1024 * 1024;

    public int MaxArtifactAgeDays { get; set; } = 7;

    public int GracePeriodHours { get; set; } = 24;

    public int MaxArtifactsPerSession { get; set; } = 100;
}
