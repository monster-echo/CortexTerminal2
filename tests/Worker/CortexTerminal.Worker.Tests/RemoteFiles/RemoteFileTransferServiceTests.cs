using System.Net;
using System.Security.Cryptography;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Worker.RemoteFiles;
using CortexTerminal.Worker.Tests.Runtime;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace CortexTerminal.Worker.Tests.RemoteFiles;

public sealed class RemoteFileTransferServiceTests : IDisposable
{
    private readonly string _root = Directory.CreateDirectory(
        Path.Combine(Path.GetTempPath(), $"corterm-rf-{Guid.NewGuid():N}")).FullName;
    private readonly FakeWorkerGatewayClient _gateway = new();
    private readonly RecordingHttpMessageHandler _http = new();
    private readonly RemoteFileTransferService _service;

    public RemoteFileTransferServiceTests()
    {
        _service = new RemoteFileTransferService(
            new HttpClient(_http),
            _gateway,
            maxTransferBytes: 1024 * 1024,
            maxListEntries: 100,
            NullLogger.Instance,
            root: _root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* temp cleanup */ }
    }

    private static string Sha256Of(byte[] content)
    {
        return Convert.ToHexString(SHA256.HashData(content)).ToLowerInvariant();
    }

    // ── ListFiles ─────────────────────────────────────────────────────

    [Fact]
    public async Task ListFiles_ReturnsListing()
    {
        Directory.CreateDirectory(Path.Combine(_root, "docs"));

        var result = await _service.HandleListFilesAsync("", CancellationToken.None);

        result.Error.Should().BeNull();
        result.Listing!.Entries.Should().ContainSingle(e => e.Name == "docs" && e.IsDirectory);
    }

    // ── MirrorUploadedFile ────────────────────────────────────────────

    [Fact]
    public async Task Mirror_WritesContentAndOverwritesExistingFile()
    {
        var content = "hello mirror"u8.ToArray();
        _http.NextResponse = new ByteArrayContent(content);
        var request = new FileMirrorRequest(
            "req-1", TargetDir: "", Filename: "note.txt", content.Length, Sha256Of(content),
            DownloadUrl: "https://s3.test/get/obj");

        var ack = await _service.HandleMirrorUploadedFileAsync(request, CancellationToken.None);

        ack.Success.Should().BeTrue();
        File.ReadAllBytes(Path.Combine(_root, "note.txt")).Should().Equal(content);

        var replaced = "replacement"u8.ToArray();
        _http.NextResponse = new ByteArrayContent(replaced);
        var second = request with { Sha256 = Sha256Of(replaced), SizeBytes = replaced.Length };
        var ack2 = await _service.HandleMirrorUploadedFileAsync(second, CancellationToken.None);
        ack2.Success.Should().BeTrue();
        File.ReadAllBytes(Path.Combine(_root, "note.txt")).Should().Equal(replaced);
    }

    [Fact]
    public async Task Mirror_ShaMismatch_FailsAndCleansTmpFile()
    {
        var request = new FileMirrorRequest(
            "req-2", "", "bad.txt", 4, Sha256Of("expected"u8.ToArray()),
            DownloadUrl: "https://s3.test/get/obj");
        _http.NextResponse = new ByteArrayContent("actual"u8.ToArray());

        var ack = await _service.HandleMirrorUploadedFileAsync(request, CancellationToken.None);

        ack.Success.Should().BeFalse();
        ack.Error!.Code.Should().Be(FileTransferErrorCode.ShaMismatch);
        File.Exists(Path.Combine(_root, "bad.txt.downloading")).Should().BeFalse();
        File.Exists(Path.Combine(_root, "bad.txt")).Should().BeFalse();
    }

    [Fact]
    public async Task Mirror_InvalidFilename_IsRejected()
    {
        var request = new FileMirrorRequest("req-3", "", "bad*name.txt", 1, "sha", "https://s3.test/get/obj");

        var ack = await _service.HandleMirrorUploadedFileAsync(request, CancellationToken.None);

        ack.Success.Should().BeFalse();
        ack.Error!.Code.Should().Be(FileTransferErrorCode.PathInvalid);
    }

    [Fact]
    public async Task Mirror_MissingTargetDir_FailsWithPathNotFound()
    {
        var content = "x"u8.ToArray();
        var request = new FileMirrorRequest("req-4", "gone-dir", "f.txt", content.Length, Sha256Of(content), "url");

        var ack = await _service.HandleMirrorUploadedFileAsync(request, CancellationToken.None);

        ack.Error!.Code.Should().Be(FileTransferErrorCode.PathNotFound);
    }

    // ── BeginFileUpload ───────────────────────────────────────────────

    [Fact]
    public async Task BeginUpload_MissingFile_FailsWithFileNotFound()
    {
        var ack = await _service.HandleBeginFileUploadAsync(
            new BeginFileUploadRequest("req-5", "nope.txt", 0), CancellationToken.None);

        ack.Success.Should().BeFalse();
        ack.Error!.Code.Should().Be(FileTransferErrorCode.FileNotFound);
    }

    [Fact]
    public async Task BeginUpload_Directory_FailsWithNotADirectory()
    {
        Directory.CreateDirectory(Path.Combine(_root, "dir"));

        var ack = await _service.HandleBeginFileUploadAsync(
            new BeginFileUploadRequest("req-6", "dir", 0), CancellationToken.None);

        ack.Error!.Code.Should().Be(FileTransferErrorCode.NotADirectory);
    }

    [Fact]
    public async Task BeginUpload_OversizedFile_FailsWithFileTooLarge()
    {
        var big = Path.Combine(_root, "big.bin");
        File.WriteAllBytes(big, new byte[1024 * 1024 + 1]);

        var ack = await _service.HandleBeginFileUploadAsync(
            new BeginFileUploadRequest("req-7", "big.bin", 0), CancellationToken.None);

        ack.Error!.Code.Should().Be(FileTransferErrorCode.FileTooLarge);
    }

    [Fact]
    public async Task BeginUpload_ValidFile_UploadsAndCompletes()
    {
        var content = "push me to s3"u8.ToArray();
        File.WriteAllBytes(Path.Combine(_root, "push.txt"), content);

        var ack = await _service.HandleBeginFileUploadAsync(
            new BeginFileUploadRequest("req-8", "push.txt", 0), CancellationToken.None);

        ack.Success.Should().BeTrue();
        var completion = await _gateway.WaitForTransferCompletionAsync();
        completion.RequestId.Should().Be("req-8");
        completion.Success.Should().BeTrue();
        _gateway.FileUploadUrlRequests.Should().ContainSingle(r => r.RequestId == "req-8");
        _gateway.FileUploadUrlRequests[0].Sha256.Should().Be(Sha256Of(content));
        _http.LastRequestContent.Should().Equal(content);
    }
}

/// <summary>
/// Serves a queued byte response for PUT/GET calls and records the request body so tests
/// can assert exactly what the worker streamed to the presigned URL.
/// </summary>
internal sealed class RecordingHttpMessageHandler : HttpMessageHandler
{
    public HttpContent? NextResponse { get; set; }
    public byte[]? LastRequestContent { get; private set; }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        if (request.Content is not null)
        {
            LastRequestContent = await request.Content.ReadAsByteArrayAsync(cancellationToken);
        }
        var content = NextResponse;
        NextResponse = null;
        return new HttpResponseMessage(HttpStatusCode.OK) { Content = content ?? new ByteArrayContent([]) };
    }
}
