using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.RemoteFiles;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Tests.Hubs;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.RemoteFiles;

public sealed class RemoteFileServiceTests
{
    private const string UserId = "user-1";
    private const string SessionId = "sess-1";
    private const string WorkerConnId = "worker-conn-1";

    private readonly FakeSessionCoordinator _sessions = new(new SessionRecord(
        SessionId, UserId, "worker-1", WorkerConnId, 120, 40,
        DateTimeOffset.UtcNow, DateTimeOffset.UtcNow));
    private readonly FakeFilesDispatcher _dispatcher = new();
    private readonly FakeS3ObjectBroker _storage = new();
    private readonly RemoteFileService _service;

    public RemoteFileServiceTests()
    {
        _service = new RemoteFileService(
            _sessions,
            _dispatcher,
            _storage,
            new PendingTransferRegistry(),
            Microsoft.Extensions.Options.Options.Create(new RemoteFilesOptions()));
    }

    // ── Listing ───────────────────────────────────────────────────────

    [Fact]
    public async Task ListAsync_ForwardsToWorker()
    {
        _dispatcher.ListingResult = new FileListingResult(
            new FileListing("docs", [new FileEntry("a.txt", false, 5, DateTimeOffset.UtcNow)], false), null);

        var listing = await _service.ListAsync(UserId, SessionId, "docs", CancellationToken.None);

        _dispatcher.ListFilesPaths.Should().ContainSingle().Which.Should().Be("docs");
        listing.Entries.Should().ContainSingle(e => e.Name == "a.txt");
    }

    [Fact]
    public async Task ListAsync_WorkerError_SurfacesCode()
    {
        _dispatcher.ListingResult = new FileListingResult(null,
            new FileOperationError(FileTransferErrorCode.PathNotFound, "gone"));

        var act = () => _service.ListAsync(UserId, SessionId, "docs", CancellationToken.None);

        (await act.Should().ThrowAsync<RemoteFileServiceException>())
            .Which.Code.Should().Be(FileTransferErrorCode.PathNotFound);
    }

    [Fact]
    public async Task ListAsync_ForeignSession_IsForbidden()
    {
        var act = () => _service.ListAsync("user-2", SessionId, "", CancellationToken.None);

        await act.Should().ThrowAsync<UnauthorizedAccessException>();
    }

    [Fact]
    public async Task ListAsync_UnknownSession_NotFound()
    {
        var act = () => _service.ListAsync(UserId, "missing-sess", "", CancellationToken.None);

        (await act.Should().ThrowAsync<RemoteFileServiceException>())
            .Which.Code.Should().Be(FileTransferErrorCode.PathNotFound);
    }

    // ── Upload flow ───────────────────────────────────────────────────

    [Fact]
    public async Task CreateUpload_IssuesTransfersKey()
    {
        var init = await _service.CreateUploadAsync(UserId, SessionId, "docs", "note.txt", 10, "sha", CancellationToken.None);

        init.UploadUrl.Should().Contain("put/transfers/");
        init.RequestId.Should().NotBeEmpty();
    }

    [Fact]
    public async Task CreateUpload_Oversize_IsRejected()
    {
        var act = () => _service.CreateUploadAsync(UserId, SessionId, "", "big.bin", 51 * 1024 * 1024, "sha", CancellationToken.None);

        (await act.Should().ThrowAsync<RemoteFileServiceException>())
            .Which.Code.Should().Be(FileTransferErrorCode.FileTooLarge);
    }

    [Fact]
    public async Task CompleteUpload_MirrorsThenDeletesTransitObject()
    {
        var init = await _service.CreateUploadAsync(UserId, SessionId, "docs", "note.txt", 10, "sha", CancellationToken.None);
        _dispatcher.MirrorAck = new FileOperationAck(true, null);

        await _service.CompleteUploadAsync(UserId, init.RequestId, CancellationToken.None);

        _dispatcher.MirrorRequests.Should().ContainSingle();
        _dispatcher.MirrorRequests[0].TargetDir.Should().Be("docs");
        _dispatcher.MirrorRequests[0].Filename.Should().Be("note.txt");
        _dispatcher.MirrorRequests[0].DownloadUrl.Should().Contain("get/transfers/");
        _storage.DeletedKeys.Should().ContainSingle(k => k == $"transfers/{init.RequestId}");
    }

    [Fact]
    public async Task CompleteUpload_MirrorFailure_SurfacesAckError()
    {
        var init = await _service.CreateUploadAsync(UserId, SessionId, "", "note.txt", 10, "sha", CancellationToken.None);
        _dispatcher.MirrorAck = new FileOperationAck(false,
            new FileOperationError(FileTransferErrorCode.ShaMismatch, "hash mismatch"));

        var act = () => _service.CompleteUploadAsync(UserId, init.RequestId, CancellationToken.None);

        (await act.Should().ThrowAsync<RemoteFileServiceException>())
            .Which.Code.Should().Be(FileTransferErrorCode.ShaMismatch);
    }

    [Fact]
    public async Task CompleteUpload_IsIdempotentOnceReady()
    {
        var init = await _service.CreateUploadAsync(UserId, SessionId, "", "note.txt", 10, "sha", CancellationToken.None);
        _dispatcher.MirrorAck = new FileOperationAck(true, null);
        await _service.CompleteUploadAsync(UserId, init.RequestId, CancellationToken.None);
        _dispatcher.MirrorRequests.Clear();

        await _service.CompleteUploadAsync(UserId, init.RequestId, CancellationToken.None);

        _dispatcher.MirrorRequests.Should().BeEmpty();
    }

    // ── Download flow ─────────────────────────────────────────────────

    [Fact]
    public async Task DownloadFlow_ValidatesThenReportsReady()
    {
        _dispatcher.BeginAck = new FileOperationAck(true, null);

        var requestId = await _service.StartDownloadAsync(UserId, SessionId, "docs/note.txt", CancellationToken.None);
        _dispatcher.BeginRequests.Should().ContainSingle(r => r.Path == "docs/note.txt");

        // Worker pushes in background: completion flips the entry to ready.
        await _service.CompleteWorkerTransferAsync(WorkerConnId, UserId,
            new CompleteFileTransferRequest(requestId, true, null), CancellationToken.None);

        var poll = await _service.PollDownloadAsync(UserId, requestId, CancellationToken.None);
        poll.Status.Should().Be(FileTransferStatus.Ready);
        poll.DownloadUrl.Should().Contain("get/transfers/");
    }

    [Fact]
    public async Task StartDownload_WorkerRejection_FailsWithCode()
    {
        _dispatcher.BeginAck = new FileOperationAck(false,
            new FileOperationError(FileTransferErrorCode.FileNotFound, "no such file"));

        var act = () => _service.StartDownloadAsync(UserId, SessionId, "nope.txt", CancellationToken.None);

        (await act.Should().ThrowAsync<RemoteFileServiceException>())
            .Which.Code.Should().Be(FileTransferErrorCode.FileNotFound);
    }

    [Fact]
    public async Task CompleteWorkerTransfer_FromWrongConnection_IsRejected()
    {
        _dispatcher.BeginAck = new FileOperationAck(true, null);
        var requestId = await _service.StartDownloadAsync(UserId, SessionId, "f.txt", CancellationToken.None);

        var act = () => _service.CompleteWorkerTransferAsync("other-conn", UserId,
            new CompleteFileTransferRequest(requestId, true, null), CancellationToken.None);

        await act.Should().ThrowAsync<RemoteFileServiceException>();
        (await _service.PollDownloadAsync(UserId, requestId, CancellationToken.None)).Status
            .Should().Be(FileTransferStatus.Pending);
    }

    [Fact]
    public async Task CompleteWorkerTransfer_Failure_ReportsErrorToPoll()
    {
        _dispatcher.BeginAck = new FileOperationAck(true, null);
        var requestId = await _service.StartDownloadAsync(UserId, SessionId, "f.txt", CancellationToken.None);

        await _service.CompleteWorkerTransferAsync(WorkerConnId, UserId,
            new CompleteFileTransferRequest(requestId, false, "disk full"), CancellationToken.None);

        var poll = await _service.PollDownloadAsync(UserId, requestId, CancellationToken.None);
        poll.Status.Should().Be(FileTransferStatus.Failed);
        poll.Error!.Message.Should().Be("disk full");
    }

    private sealed class FakeFilesDispatcher : IWorkerCommandDispatcher
    {
        public FileListingResult ListingResult { get; set; } =
            new(new FileListing("", [], false), null);
        public FileOperationAck MirrorAck { get; set; } = new(true, null);
        public FileOperationAck BeginAck { get; set; } = new(true, null);
        public List<string> ListFilesPaths { get; } = [];
        public List<FileMirrorRequest> MirrorRequests { get; } = [];
        public List<BeginFileUploadRequest> BeginRequests { get; } = [];

        public Task<FileListingResult> ListFilesAsync(string workerConnectionId, string relativePath, CancellationToken ct)
        {
            ListFilesPaths.Add(relativePath);
            return Task.FromResult(ListingResult);
        }

        public Task<FileOperationAck> MirrorUploadedFileAsync(string workerConnectionId, FileMirrorRequest request, CancellationToken ct)
        {
            MirrorRequests.Add(request);
            return Task.FromResult(MirrorAck);
        }

        public Task<FileOperationAck> BeginFileUploadAsync(string workerConnectionId, BeginFileUploadRequest request, CancellationToken ct)
        {
            BeginRequests.Add(request);
            return Task.FromResult(BeginAck);
        }

        public Task StartSessionAsync(string w, StartSessionCommand c, CancellationToken ct) => Task.CompletedTask;
        public Task WriteInputAsync(string w, WriteInputFrame f, CancellationToken ct) => Task.CompletedTask;
        public Task ProbeLatencyAsync(string w, LatencyProbeFrame f, CancellationToken ct) => Task.CompletedTask;
        public Task ResizeSessionAsync(string w, ResizePtyRequest r, CancellationToken ct) => Task.CompletedTask;
        public Task CloseSessionAsync(string w, CloseSessionRequest r, CancellationToken ct) => Task.CompletedTask;
        public Task UpgradeWorkerAsync(string w, UpgradeWorkerCommand c, CancellationToken ct) => Task.CompletedTask;
        public Task<IReadOnlyList<TerminalChunk>> RequestScrollbackAsync(string w, string s, CancellationToken ct)
            => Task.FromResult<IReadOnlyList<TerminalChunk>>(Array.Empty<TerminalChunk>());
        public Task<ProbePortResponse> ProbeTunnelPortAsync(string w, int p, CancellationToken ct)
            => Task.FromResult(new ProbePortResponse(true, null));
        public Task<TunnelHttpResponse> SendTunnelHttpRequestAsync(string w, string t, TunnelHttpRequest r, CancellationToken ct)
            => Task.FromResult(new TunnelHttpResponse(200, new Dictionary<string, string[]>(), Array.Empty<byte>(), null));
    }
}
