using CortexTerminal.Contracts.Sessions;

namespace CortexTerminal.Gateway.Storage;

public interface IArtifactStorage
{
    Task<UploadUrlResponse> GenerateUploadUrlAsync(string sessionId, string filename, CancellationToken ct);

    Task<DownloadUrlResponse> GenerateDownloadUrlAsync(string sessionId, string filename, CancellationToken ct);

    Task DeleteObjectAsync(string sessionId, string filename, CancellationToken ct);

    Task DeleteSessionPrefixAsync(string sessionId, CancellationToken ct);

    Task<long> GetObjectSizeAsync(string sessionId, string filename, CancellationToken ct);

    Task<bool> ObjectExistsAsync(string sessionId, string filename, CancellationToken ct);
}
