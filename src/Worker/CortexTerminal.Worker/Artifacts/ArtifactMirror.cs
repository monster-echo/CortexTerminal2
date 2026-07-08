using System.Security.Cryptography;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Artifacts;

/// <summary>
/// Downloads Console-uploaded artifacts into the session's local artifacts directory so the
/// running shell (and AI agents) can read them via <c>$CORTERM_ARTIFACTS_DIR</c>. The Worker never
/// holds S3 credentials: every download is performed against a presigned GET URL that the Gateway
/// attaches to <see cref="NotifyArtifactUploadedFrame"/>.
/// </summary>
public sealed class ArtifactMirror(
    HttpClient httpClient,
    ILogger<ArtifactMirror> logger)
{
    public async Task DownloadFromGatewayAsync(NotifyArtifactUploadedFrame frame, CancellationToken ct)
    {
        if (!ArtifactFilenameValidator.TryValidate(frame.Filename, out var reason))
        {
            logger.LogWarning("ArtifactMirror skip download: invalid filename {Filename} ({Reason}).", frame.Filename, reason);
            return;
        }

        var artifactsDir = ArtifactPaths.GetSessionArtifactsDir(frame.SessionId);
        Directory.CreateDirectory(artifactsDir);
        var targetPath = Path.Combine(artifactsDir, frame.Filename);

        var tmpPath = targetPath + ".downloading";
        try
        {
            using var resp = await httpClient.GetAsync(frame.DownloadUrl, HttpCompletionOption.ResponseHeadersRead, ct);
            resp.EnsureSuccessStatusCode();

            await using (var fileStream = File.Create(tmpPath))
            {
                await resp.Content.CopyToAsync(fileStream, ct);
            }

            if (!string.IsNullOrEmpty(frame.ContentSha256))
            {
                var actual = await ComputeSha256Async(tmpPath, ct);
                if (!string.Equals(actual, frame.ContentSha256, StringComparison.OrdinalIgnoreCase))
                {
                    logger.LogError("ArtifactMirror sha256 mismatch for {Filename}: expected {Expected}, got {Actual}.",
                        frame.Filename, frame.ContentSha256, actual);
                    File.Delete(tmpPath);
                    return;
                }
            }

            File.Move(tmpPath, targetPath, overwrite: true);
            logger.LogInformation("ArtifactMirror downloaded {Filename} into {Dir} ({Size} bytes).",
                frame.Filename, artifactsDir, frame.SizeBytes);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "ArtifactMirror failed to download {Filename} for session {SessionId}.",
                frame.Filename, frame.SessionId);
            try { if (File.Exists(tmpPath)) File.Delete(tmpPath); } catch { /* best-effort */ }
        }
    }

    public static async Task<string> ComputeSha256Async(string path, CancellationToken ct)
    {
        await using var stream = File.OpenRead(path);
        using var sha = SHA256.Create();
        var hash = await sha.ComputeHashAsync(stream, ct);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}
