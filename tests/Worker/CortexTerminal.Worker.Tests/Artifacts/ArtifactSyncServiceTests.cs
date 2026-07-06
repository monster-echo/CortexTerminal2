using System.Net;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Artifacts;
using CortexTerminal.Worker.Tests.Artifacts.Fakes;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;

namespace CortexTerminal.Worker.Tests.Artifacts;

/// <summary>
/// ArtifactSyncService pipeline tests. The service uses real FileSystemWatcher + real Task.Delay
/// for debounce (1s) and stability (1s), so tests must wait ~2s for a file to flow through. We
/// trigger via StartAsync's existing-file sweep to avoid FS-watcher timing flakes, and use the
/// fake gateway's per-filename task gates for deterministic assertions.
/// </summary>
public sealed class ArtifactSyncServiceTests
{
    private static readonly TimeSpan TestTimeout = TimeSpan.FromSeconds(15);

    [Fact]
    public async Task StartAsync_SweepsExistingFile_RequestsUploadUrlAndPutsToStorage()
    {
        var (service, gateway, http, dir) = await BuildAsync("sess-1", maxSizeBytes: 1024 * 1024);
        await using var _ = service;
        using var __ = TempDirScope(dir);
        var filename = "hello.txt";
        var path = Path.Combine(dir, filename);
        await File.WriteAllTextAsync(path, "hello world");

        await service.StartAsync(CancellationToken.None);

        var req = await gateway.WaitForUploadUrlRequestAsync(filename, TestTimeout);
        req.SessionId.Should().Be("sess-1");
        req.Filename.Should().Be(filename);
        req.SizeBytes.Should().Be("hello world".Length);
        req.Origin.Should().Be(ArtifactOrigin.Worker);
        req.ContentSha256.Should().NotBeNullOrEmpty();

        await gateway.WaitForAnyCompleteRequestAsync(TestTimeout);
        var put = http.Puts.Should().ContainSingle().Which;
        put.Url.Should().StartWith("https://fake-s3.local/sess-1/hello.txt");
        put.Body.Should().Equal("hello world"u8.ToArray());

        gateway.CompleteRequests.Should().ContainSingle()
            .Which.ArtifactId.Should().Be($"artifact-{filename}");
    }

    [Fact]
    public async Task Pipeline_TempFile_NeverReachesGateway()
    {
        var (service, gateway, _, dir) = await BuildAsync("sess-1");
        await using var _ = service;
        using var __ = TempDirScope(dir);
        foreach (var tempName in new[] { ".swp", "tmp~", "edit.tmp", "data.bak", ".DS_Store" })
        {
            await File.WriteAllTextAsync(Path.Combine(dir, tempName), "noise");
        }

        await service.StartAsync(CancellationToken.None);
        await Task.Delay(500); // sweep is synchronous; nothing should land in the gateway

        gateway.UploadUrlRequests.Should().BeEmpty();
        gateway.CompleteRequests.Should().BeEmpty();
    }

    [Fact]
    public async Task Pipeline_OversizedFile_SkipsBeforeRequestingUrl()
    {
        var (service, gateway, _, dir) = await BuildAsync("sess-1", maxSizeBytes: 8);
        await using var _ = service;
        using var __ = TempDirScope(dir);
        var filename = "big.txt";
        await File.WriteAllTextAsync(Path.Combine(dir, filename), "this is way too big");

        await service.StartAsync(CancellationToken.None);

        // Stability check will pass (file is stable); size check then rejects and returns before URL request.
        await Task.Delay(3000); // 1s debounce + 1s stability + slack
        gateway.UploadUrlRequests.Should().BeEmpty();
    }

    [Fact]
    public async Task Pipeline_SameSha_AlreadyUploaded_DedupesSecondRun()
    {
        var (service, gateway, _, dir) = await BuildAsync("sess-1");
        await using var _ = service;
        using var __ = TempDirScope(dir);
        var filename = "once.txt";
        await File.WriteAllTextAsync(Path.Combine(dir, filename), "same-content");

        await service.StartAsync(CancellationToken.None);
        await gateway.WaitForUploadUrlRequestAsync(filename, TestTimeout);
        await gateway.WaitForAnyCompleteRequestAsync(TestTimeout);

        // Second sweep should be deduped by _lastUploadedHash and NOT issue a second URL request.
        gateway.UploadUrlRequests.Clear();
        await service.StartAsync(CancellationToken.None);
        await Task.Delay(2500); // debounce + stability + slack
        gateway.UploadUrlRequests.Should().BeEmpty();
    }

    [Fact]
    public async Task Pipeline_CompleteAckFailure_DoesNotRecordDedupHash()
    {
        var (service, gateway, _, dir) = await BuildAsync("sess-1");
        await using var _ = service;
        using var __ = TempDirScope(dir);
        // Make the Gateway reject every completion — dedup hash should not be recorded.
        gateway.CompleteResponder = _ => new CompleteArtifactAck(Success: false, Error: "sha-mismatch");

        var filename = "rejected.txt";
        await File.WriteAllTextAsync(Path.Combine(dir, filename), "payload");

        await service.StartAsync(CancellationToken.None);
        await gateway.WaitForUploadUrlRequestAsync(filename, TestTimeout);
        await gateway.WaitForAnyCompleteRequestAsync(TestTimeout);

        // Second sweep — since dedup hash wasn't recorded, the URL request fires again.
        gateway.UploadUrlRequests.Clear();
        await service.StartAsync(CancellationToken.None);
        await gateway.WaitForUploadUrlRequestAsync(filename, TestTimeout);
        // One or more URL requests may fire (FS watcher race); the key assertion is that at least one did.
        gateway.UploadUrlRequests.Should().NotBeEmpty();
    }

    [Fact]
    public async Task Pipeline_GatewayReturnsEmptyUploadUrl_SkipsPut()
    {
        var (service, gateway, http, dir) = await BuildAsync("sess-1");
        await using var _ = service;
        using var __ = TempDirScope(dir);
        gateway.UploadUrlResponder = _ => new UploadUrlResponse("art-1", UploadUrl: "", S3Key: "k", ExpiresAt: DateTimeOffset.UtcNow);

        var filename = "empty.txt";
        await File.WriteAllTextAsync(Path.Combine(dir, filename), "x");

        await service.StartAsync(CancellationToken.None);
        await gateway.WaitForUploadUrlRequestAsync(filename, TestTimeout);
        await Task.Delay(1000); // give the empty-URL branch time to bail out

        http.Puts.Should().BeEmpty();
        gateway.CompleteRequests.Should().BeEmpty();
    }

    [Fact]
    public async Task Pipeline_S3PutFailure_DoesNotReportComplete()
    {
        var (service, gateway, http, dir) = await BuildAsync("sess-1");
        await using var _ = service;
        using var __ = TempDirScope(dir);
        http.Responder = _ => new HttpResponseMessage(HttpStatusCode.InternalServerError);

        var filename = "put-fail.txt";
        await File.WriteAllTextAsync(Path.Combine(dir, filename), "data");

        await service.StartAsync(CancellationToken.None);
        await gateway.WaitForUploadUrlRequestAsync(filename, TestTimeout);
        await Task.Delay(1500); // PUT attempt + slack

        // One or more PUTs may fire (FS watcher race) — what matters is that none of them succeeded,
        // so CompleteArtifactUploadAsync must never be called.
        http.Puts.Should().NotBeEmpty();
        gateway.CompleteRequests.Should().BeEmpty();
    }

    [Fact]
    public async Task OnFileDeleted_ReportsDeletedFrameToGateway()
    {
        var (service, gateway, _, dir) = await BuildAsync("sess-1");
        await using var _ = service;
        using var __ = TempDirScope(dir);
        var filename = "deletable.txt";
        var path = Path.Combine(dir, filename);
        await File.WriteAllTextAsync(path, "x");
        await service.StartAsync(CancellationToken.None);
        await gateway.WaitForUploadUrlRequestAsync(filename, TestTimeout);
        await gateway.WaitForAnyCompleteRequestAsync(TestTimeout);

        File.Delete(path);

        var report = await gateway.WaitForDeleteReportAsync(filename, TestTimeout);
        report.SessionId.Should().Be("sess-1");
        report.Filename.Should().Be(filename);
    }

    [Fact]
    public async Task DisposeAsync_DoesNotThrowWithPendingUploads()
    {
        var (service, gateway, _, dir) = await BuildAsync("sess-1");
        using var __ = TempDirScope(dir);
        var filename = "dispose.txt";
        await File.WriteAllTextAsync(Path.Combine(dir, filename), "x");
        await service.StartAsync(CancellationToken.None);
        await gateway.WaitForUploadUrlRequestAsync(filename, TestTimeout); // pending upload still in flight

        var act = async () => await service.DisposeAsync();
        await act.Should().NotThrowAsync();
    }

    private static async Task<(ArtifactSyncService service, FakeWorkerGatewayClient gateway, RecordingHttpMessageHandler http, string dir)> BuildAsync(
        string sessionId,
        long maxSizeBytes = 50 * 1024 * 1024)
    {
        var dir = Path.Combine(Path.GetTempPath(), $"corterm-test-{Guid.NewGuid():N}", "artifacts");
        Directory.CreateDirectory(dir);
        var gateway = new FakeWorkerGatewayClient();
        var http = new RecordingHttpMessageHandler();
        var httpClient = new HttpClient(http);
        var service = new ArtifactSyncService(
            sessionId,
            dir,
            gateway,
            httpClient,
            maxSizeBytes,
            NullLogger<ArtifactSyncService>.Instance);
        await Task.Yield();
        return (service, gateway, http, dir);
    }

    private static IDisposable TempDirScope(string dir)
        => new TempDirDisposable(dir);

    private sealed class TempDirDisposable(string dir) : IDisposable
    {
        public void Dispose()
        {
            try { Directory.Delete(Path.GetDirectoryName(dir)!, recursive: true); }
            catch { /* best-effort cleanup */ }
        }
    }
}
