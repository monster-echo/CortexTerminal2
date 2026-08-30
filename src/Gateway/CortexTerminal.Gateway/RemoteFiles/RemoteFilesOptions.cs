namespace CortexTerminal.Gateway.RemoteFiles;

public sealed class RemoteFilesOptions
{
    public const string SectionName = "RemoteFiles";

    /// <summary>Per-file transfer cap. 50 MB matches the Harmony client, which buffers a whole file in memory to PUT it.</summary>
    public long MaxTransferSizeBytes { get; set; } = 50 * 1024 * 1024;

    /// <summary>Per-listing entry cap; listings beyond this come back truncated.</summary>
    public int MaxListEntries { get; set; } = 2000;

    /// <summary>How long an in-flight (or finished) transfer entry lives in the registry before it is swept.</summary>
    public TimeSpan PendingTransferTtl { get; set; } = TimeSpan.FromMinutes(15);

    /// <summary>Age at which an unconsumed S3 transfer object becomes eligible for deletion.</summary>
    public TimeSpan ObjectRetention { get; set; } = TimeSpan.FromHours(1);

    public TimeSpan CleanupInterval { get; set; } = TimeSpan.FromMinutes(10);

    public TimeSpan ListRpcTimeout { get; set; } = TimeSpan.FromSeconds(10);

    public TimeSpan BeginRpcTimeout { get; set; } = TimeSpan.FromSeconds(10);

    /// <summary>Mirroring a phone upload means the worker re-downloads up to MaxTransferSizeBytes from S3 — allow slow links.</summary>
    public TimeSpan MirrorRpcTimeout { get; set; } = TimeSpan.FromMinutes(2);
}
