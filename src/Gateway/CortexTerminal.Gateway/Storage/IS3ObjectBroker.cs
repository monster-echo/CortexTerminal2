namespace CortexTerminal.Gateway.Storage;

/// <summary>A presigned URL plus the moment it stops working.</summary>
public sealed record PresignedUrl(string Url, DateTimeOffset ExpiresAt);

/// <summary>One object returned by a prefix listing.</summary>
public sealed record StoredObject(string Key, DateTimeOffset LastModified);

/// <summary>
/// Key-direct operations against the S3-compatible object store. Callers own the full key
/// (e.g. "transfers/{requestId}", "feedback/{userId}/{guid}.ext") — the broker has no
/// opinion about key layout. Neither phones nor workers hold storage credentials; every
/// byte moves through presigned URLs issued here.
/// </summary>
public interface IS3ObjectBroker
{
    Task<PresignedUrl> GeneratePutUrlAsync(string key, CancellationToken ct);

    Task<PresignedUrl> GenerateGetUrlAsync(string key, CancellationToken ct);

    Task DeleteAsync(string key, CancellationToken ct);

    Task<IReadOnlyList<StoredObject>> ListByPrefixAsync(string prefix, CancellationToken ct);
}
