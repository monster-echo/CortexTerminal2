using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Storage;
using CortexTerminal.Gateway.Workers;
using Microsoft.Extensions.Options;

namespace CortexTerminal.Gateway.RemoteFiles;

/// <summary>
/// A remote-file operation failed with a machine-readable code from
/// <see cref="FileTransferErrorCode"/>; REST endpoints map the code to an HTTP status.
/// </summary>
public sealed class RemoteFileServiceException(string code, string message)
    : Exception(message)
{
    public string Code { get; } = code;
}

/// <summary>REST response: step 1 of the phone upload flow.</summary>
public sealed record UploadInitResult(string RequestId, string UploadUrl, DateTimeOffset ExpiresAt);

/// <summary>REST response: download poll (phone polls every ~2s until ready/failed).</summary>
public sealed record DownloadPollResult(string Status, string? DownloadUrl, DateTimeOffset? ExpiresAt, FileOperationError? Error);

/// <summary>
/// Orchestrates the phone ⇄ worker ⇄ S3 remote-file flows. The gateway is a signaling
/// hub: it never touches file bytes, only presigned URLs and worker RPCs. Transfer state
/// lives in <see cref="PendingTransferRegistry"/> (in-memory, TTL-swept); S3 objects under
/// the "transfers/" prefix are transit-only and reaped by <see cref="TransferObjectCleanupService"/>.
/// </summary>
public sealed class RemoteFileService(
    ISessionCoordinator sessions,
    IWorkerCommandDispatcher workerCommands,
    IS3ObjectBroker storage,
    PendingTransferRegistry registry,
    IOptions<RemoteFilesOptions> options)
{
    private readonly RemoteFilesOptions _options = options.Value;

    /// <summary>Live listing of one directory of the session root on the worker.</summary>
    public async Task<FileListing> ListAsync(string userId, string sessionId, string? path, CancellationToken ct)
    {
        var session = EnsureSessionOwnedByUser(userId, sessionId);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(_options.ListRpcTimeout);

        var result = await workerCommands.ListFilesAsync(session.WorkerConnectionId!, path ?? string.Empty, timeout.Token);
        if (result.Error is not null)
        {
            throw new RemoteFileServiceException(result.Error.Code, result.Error.Message);
        }
        return result.Listing ?? throw new RemoteFileServiceException(
            FileTransferErrorCode.TransferFailed, "worker returned an empty listing result");
    }

    /// <summary>
    /// Step 1 of the phone upload flow: register a transfer, hand back a presigned PUT for
    /// the transit object. The follow-up <see cref="CompleteUploadAsync"/> makes the worker
    /// mirror the object into the target directory.
    /// </summary>
    public async Task<UploadInitResult> CreateUploadAsync(
        string userId, string sessionId, string dirPath, string filename, long sizeBytes, string sha256, CancellationToken ct)
    {
        var session = EnsureSessionOwnedByUser(userId, sessionId);
        if (!RemoteFileNameValidator.TryValidateSegment(filename, out var reason))
        {
            throw new RemoteFileServiceException(FileTransferErrorCode.PathInvalid, reason);
        }
        if (sizeBytes <= 0)
        {
            throw new RemoteFileServiceException(FileTransferErrorCode.PathInvalid, "sizeBytes must be positive");
        }
        if (sizeBytes > _options.MaxTransferSizeBytes)
        {
            throw new RemoteFileServiceException(FileTransferErrorCode.FileTooLarge,
                $"file exceeds the {_options.MaxTransferSizeBytes / (1024 * 1024)} MB transfer limit");
        }

        var requestId = NewRequestId();
        var put = await storage.GeneratePutUrlAsync(TransfersKey(requestId), ct);
        registry.Upsert(new PendingTransfer(
            RequestId: requestId,
            SessionId: sessionId,
            UserId: userId,
            WorkerConnectionId: session.WorkerConnectionId!,
            TargetPath: dirPath,
            Filename: filename,
            SizeBytes: sizeBytes,
            Sha256: sha256,
            Status: FileTransferStatus.Pending,
            Error: null,
            CreatedAtUtc: DateTimeOffset.UtcNow));
        return new UploadInitResult(requestId, put.Url, put.ExpiresAt);
    }

    /// <summary>
    /// Step 3 of the phone upload flow: have the worker mirror the transit object into the
    /// target directory. Synchronous on purpose — the 200 response means the file is on
    /// disk. Idempotent: a repeat call on a ready transfer succeeds without re-mirroring.
    /// </summary>
    public async Task CompleteUploadAsync(string userId, string requestId, CancellationToken ct)
    {
        var entry = registry.GetOwned(requestId, userId);
        if (entry.Status == FileTransferStatus.Ready)
        {
            return;
        }

        var get = await storage.GenerateGetUrlAsync(TransfersKey(requestId), ct);
        var mirror = new FileMirrorRequest(
            RequestId: requestId,
            TargetDir: entry.TargetPath,
            Filename: entry.Filename!,
            SizeBytes: entry.SizeBytes,
            Sha256: entry.Sha256!,
            DownloadUrl: get.Url);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(_options.MirrorRpcTimeout);
        var ack = await workerCommands.MirrorUploadedFileAsync(entry.WorkerConnectionId, mirror, timeout.Token);
        if (!ack.Success)
        {
            var error = ack.Error ?? new FileOperationError(FileTransferErrorCode.TransferFailed, "mirror failed");
            throw new RemoteFileServiceException(error.Code, error.Message);
        }

        registry.TryUpdate(requestId, t => t with
        {
            Status = FileTransferStatus.Ready,
            TerminalAtUtc = DateTimeOffset.UtcNow,
        });
        await storage.DeleteAsync(TransfersKey(requestId), ct);
    }

    /// <summary>
    /// Step 1 of the phone download flow: register a transfer and have the worker validate
    /// the file synchronously, then push it to S3 in the background. The returned requestId
    /// is polled until <see cref="PollDownloadAsync"/> reports ready.
    /// </summary>
    public async Task<string> StartDownloadAsync(string userId, string sessionId, string path, CancellationToken ct)
    {
        var session = EnsureSessionOwnedByUser(userId, sessionId);
        var requestId = NewRequestId();
        registry.Upsert(new PendingTransfer(
            RequestId: requestId,
            SessionId: sessionId,
            UserId: userId,
            WorkerConnectionId: session.WorkerConnectionId!,
            TargetPath: path,
            Filename: null,
            SizeBytes: 0,
            Sha256: null,
            Status: FileTransferStatus.Pending,
            Error: null,
            CreatedAtUtc: DateTimeOffset.UtcNow));

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(_options.BeginRpcTimeout);
        FileOperationAck ack;
        try
        {
            ack = await workerCommands.BeginFileUploadAsync(
                session.WorkerConnectionId!, new BeginFileUploadRequest(requestId, path, SizeBytes: 0), timeout.Token);
        }
        catch
        {
            registry.Remove(requestId);
            throw;
        }
        if (!ack.Success)
        {
            registry.Remove(requestId);
            var error = ack.Error ?? new FileOperationError(FileTransferErrorCode.TransferFailed, "worker rejected the download");
            throw new RemoteFileServiceException(error.Code, error.Message);
        }
        return requestId;
    }

    /// <summary>Step 2 of the phone download flow: poll until the transfer is ready or failed.</summary>
    public async Task<DownloadPollResult> PollDownloadAsync(string userId, string requestId, CancellationToken ct)
    {
        var entry = registry.GetOwned(requestId, userId);
        if (entry.Status == FileTransferStatus.Pending)
        {
            return new DownloadPollResult(FileTransferStatus.Pending, DownloadUrl: null, ExpiresAt: null, Error: null);
        }
        if (entry.Status == FileTransferStatus.Failed)
        {
            return new DownloadPollResult(FileTransferStatus.Failed, DownloadUrl: null, ExpiresAt: null, entry.Error);
        }

        var get = await storage.GenerateGetUrlAsync(TransfersKey(requestId), ct);
        return new DownloadPollResult(FileTransferStatus.Ready, get.Url, get.ExpiresAt, Error: null);
    }

    /// <summary>
    /// Worker RPC (from <see cref="Hubs.WorkerHub.RequestFileUploadUrl"/>): hand a presigned
    /// PUT to the owning worker for an in-flight download transfer.
    /// </summary>
    public async Task<TransferUploadUrlResponse> CreateWorkerUploadUrlAsync(
        string workerConnectionId, string ownerUserId, FileUploadUrlRequest request, CancellationToken ct)
    {
        var entry = EnsureWorkerOwned(request.RequestId, ownerUserId, workerConnectionId);
        if (entry.Status != FileTransferStatus.Pending)
        {
            throw new RemoteFileServiceException(FileTransferErrorCode.TransferFailed, $"transfer is {entry.Status}");
        }
        var put = await storage.GeneratePutUrlAsync(TransfersKey(request.RequestId), ct);
        return new TransferUploadUrlResponse(put.Url, put.ExpiresAt);
    }

    /// <summary>
    /// Worker RPC (from <see cref="Hubs.WorkerHub.CompleteFileTransfer"/>): flip the transfer
    /// to ready, or record the failure so the phone's poll reports it.
    /// </summary>
    public Task CompleteWorkerTransferAsync(
        string workerConnectionId, string ownerUserId, CompleteFileTransferRequest request, CancellationToken ct)
    {
        var entry = EnsureWorkerOwned(request.RequestId, ownerUserId, workerConnectionId);
        var now = DateTimeOffset.UtcNow;
        if (!request.Success)
        {
            registry.TryUpdate(request.RequestId, t => t with
            {
                Status = FileTransferStatus.Failed,
                Error = new FileOperationError(FileTransferErrorCode.TransferFailed, request.Error ?? "worker upload failed"),
                TerminalAtUtc = now,
            });
            return Task.CompletedTask;
        }

        registry.TryUpdate(request.RequestId, t => t with
        {
            Status = FileTransferStatus.Ready,
            Sha256 = entry.Sha256,
            TerminalAtUtc = now,
        });
        return Task.CompletedTask;
    }

    private PendingTransfer EnsureWorkerOwned(string requestId, string ownerUserId, string workerConnectionId)
    {
        var entry = registry.GetOwned(requestId, ownerUserId);
        if (entry.WorkerConnectionId != workerConnectionId)
        {
            throw new RemoteFileServiceException(FileTransferErrorCode.TransferNotFound, "transfer belongs to another worker connection");
        }
        return entry;
    }

    private SessionRecord EnsureSessionOwnedByUser(string userId, string sessionId)
    {
        if (!sessions.TryGetSession(sessionId, out var session))
        {
            throw new RemoteFileServiceException(FileTransferErrorCode.PathNotFound, "Session not found");
        }
        if (session.UserId != userId)
        {
            throw new UnauthorizedAccessException("Session belongs to another user");
        }
        return session;
    }

    private static string NewRequestId() => Guid.NewGuid().ToString("N");

    private static string TransfersKey(string requestId) => $"transfers/{requestId}";
}
