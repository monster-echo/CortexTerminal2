using System.Net;
using System.Security.Cryptography;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Artifacts;
using CortexTerminal.Worker.Tests.Artifacts.Fakes;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;

namespace CortexTerminal.Worker.Tests.Artifacts;

/// <summary>
/// ArtifactMirror downloads an artifact from a Gateway-provided presigned URL into the session's
/// local artifacts dir, optionally SHA256-verifying the bytes. Tests isolate the local mirror dir
/// via a unique sessionId and clean it up afterwards.
/// </summary>
public sealed class ArtifactMirrorTests
{
    [Fact]
    public async Task DownloadFromGatewayAsync_ValidSha_MovesTempToFinalPath()
    {
        var sessionId = $"mirror-{Guid.NewGuid():N}";
        var payload = "hello mirror"u8.ToArray();
        var sha = Sha256Hex(payload);
        var (mirror, http) = BuildMirror(payload);
        using var _ = SessionScope(sessionId);
        var frame = new NotifyArtifactUploadedFrame(sessionId, "data.bin", "https://gw/fake/data.bin", payload.Length, sha);

        await mirror.DownloadFromGatewayAsync(frame, CancellationToken.None);

        http.Requests.Should().ContainSingle();
        var dir = ArtifactPaths.GetSessionArtifactsDir(sessionId);
        File.Exists(Path.Combine(dir, "data.bin")).Should().BeTrue();
        File.ReadAllBytes(Path.Combine(dir, "data.bin")).Should().Equal(payload);
        // .downloading temp must have been moved, not copied.
        File.Exists(Path.Combine(dir, "data.bin.downloading")).Should().BeFalse();
    }

    [Fact]
    public async Task DownloadFromGatewayAsync_ShaMismatch_DeletesTempFile()
    {
        var sessionId = $"mirror-{Guid.NewGuid():N}";
        var payload = "real-content"u8.ToArray();
        var wrongSha = Sha256Hex("different-bytes"u8.ToArray());
        var (mirror, http) = BuildMirror(payload);
        using var _ = SessionScope(sessionId);
        var frame = new NotifyArtifactUploadedFrame(sessionId, "bad.bin", "https://gw/fake/bad.bin", payload.Length, wrongSha);

        await mirror.DownloadFromGatewayAsync(frame, CancellationToken.None);

        var dir = ArtifactPaths.GetSessionArtifactsDir(sessionId);
        File.Exists(Path.Combine(dir, "bad.bin")).Should().BeFalse();
        File.Exists(Path.Combine(dir, "bad.bin.downloading")).Should().BeFalse();
        http.Requests.Should().ContainSingle();
    }

    [Fact]
    public async Task DownloadFromGatewayAsync_NoShaSpecified_WritesBytesAnyway()
    {
        var sessionId = $"mirror-{Guid.NewGuid():N}";
        var payload = "no-sha"u8.ToArray();
        var (mirror, _) = BuildMirror(payload);
        using var _ = SessionScope(sessionId);
        var frame = new NotifyArtifactUploadedFrame(sessionId, "open.bin", "https://gw/fake/open.bin", payload.Length, ContentSha256: "");

        await mirror.DownloadFromGatewayAsync(frame, CancellationToken.None);

        var dir = ArtifactPaths.GetSessionArtifactsDir(sessionId);
        File.Exists(Path.Combine(dir, "open.bin")).Should().BeTrue();
        File.ReadAllBytes(Path.Combine(dir, "open.bin")).Should().Equal(payload);
    }

    [Fact]
    public async Task DownloadFromGatewayAsync_InvalidFilename_DoesNotCallGateway()
    {
        var sessionId = $"mirror-{Guid.NewGuid():N}";
        var (mirror, http) = BuildMirror("x"u8.ToArray());
        using var _ = SessionScope(sessionId);
        // Path-traversal-style names are rejected by ArtifactFilenameValidator.
        var frame = new NotifyArtifactUploadedFrame(sessionId, "../escape.bin", "https://gw/fake", 1, "deadbeef");

        await mirror.DownloadFromGatewayAsync(frame, CancellationToken.None);

        http.Requests.Should().BeEmpty();
    }

    [Fact]
    public async Task DownloadFromGatewayAsync_HttpFailure_DoesNotLeaveTempFile()
    {
        var sessionId = $"mirror-{Guid.NewGuid():N}";
        var http = new RecordingHttpMessageHandler
        {
            Responder = _ => new HttpResponseMessage(HttpStatusCode.InternalServerError)
        };
        var mirror = new ArtifactMirror(new HttpClient(http), NullLogger<ArtifactMirror>.Instance);
        using var _ = SessionScope(sessionId);
        var frame = new NotifyArtifactUploadedFrame(sessionId, "fail.bin", "https://gw/fake/fail.bin", 4, "");

        var act = () => mirror.DownloadFromGatewayAsync(frame, CancellationToken.None);
        await act.Should().NotThrowAsync(); // ArtifactMirror swallows the exception.

        var dir = ArtifactPaths.GetSessionArtifactsDir(sessionId);
        File.Exists(Path.Combine(dir, "fail.bin")).Should().BeFalse();
        File.Exists(Path.Combine(dir, "fail.bin.downloading")).Should().BeFalse();
    }

    [Fact]
    public async Task ComputeSha256Async_MatchesBuiltInSha256()
    {
        var path = Path.Combine(Path.GetTempPath(), $"sha-{Guid.NewGuid():N}.bin");
        var payload = "compute-me"u8.ToArray();
        await File.WriteAllBytesAsync(path, payload);
        try
        {
            var expected = Sha256Hex(payload);
            var actual = await ArtifactMirror.ComputeSha256Async(path, CancellationToken.None);
            actual.Should().Be(expected);
        }
        finally
        {
            File.Delete(path);
        }
    }

    private static (ArtifactMirror mirror, RecordingHttpMessageHandler http) BuildMirror(byte[] payload)
    {
        var http = new RecordingHttpMessageHandler
        {
            Responder = _ => new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent(payload)
            }
        };
        var mirror = new ArtifactMirror(new HttpClient(http), NullLogger<ArtifactMirror>.Instance);
        return (mirror, http);
    }

    private static string Sha256Hex(byte[] payload)
    {
        using var sha = SHA256.Create();
        return Convert.ToHexString(sha.ComputeHash(payload)).ToLowerInvariant();
    }

    private static IDisposable SessionScope(string sessionId)
        => new SessionScopeDisposable(sessionId);

    private sealed class SessionScopeDisposable(string sessionId) : IDisposable
    {
        public void Dispose() => ArtifactPaths.DeleteSessionDir(sessionId);
    }
}
