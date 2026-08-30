using System.Security.Cryptography;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Worker.Registration;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.RemoteFiles;

/// <summary>
/// Handles the three Gateway→Worker remote-file commands (ListFiles, MirrorUploadedFile,
/// BeginFileUpload) against the session root — the PTY cwd, the user's home. The Worker
/// never holds S3 credentials: mirroring downloads via a presigned GET that the Gateway
/// attaches to the request, and phone downloads push via a presigned PUT obtained through
/// the <see cref="IWorkerGatewayClient.RequestFileUploadUrlAsync"/> RPC.
/// </summary>
public sealed class RemoteFileTransferService
{
    private readonly string _root;
    private readonly long _maxTransferBytes;
    private readonly RemoteDirectoryLister _lister;
    private readonly IWorkerGatewayClient _gatewayClient;
    private readonly HttpClient _httpClient;
    private readonly ILogger _logger;
    private readonly SemaphoreSlim _uploadSlots = new(4, 4);

    public RemoteFileTransferService(
        HttpClient httpClient,
        IWorkerGatewayClient gatewayClient,
        long maxTransferBytes,
        int maxListEntries,
        ILogger logger,
        string? root = null)
    {
        _httpClient = httpClient;
        _gatewayClient = gatewayClient;
        _maxTransferBytes = maxTransferBytes;
        _logger = logger;
        _root = string.IsNullOrEmpty(root)
            ? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
            : root;
        _lister = new RemoteDirectoryLister(_root, maxListEntries);
    }

    public Task<FileListingResult> HandleListFilesAsync(string? relativePath, CancellationToken ct)
        => Task.FromResult(_lister.List(relativePath));

    /// <summary>
    /// Persist a phone upload: stream the S3 object at <paramref name="request"/>'s presigned
    /// GET into TargetDir/Filename, verify SHA256, atomically replace any existing file.
    /// </summary>
    public async Task<FileOperationAck> HandleMirrorUploadedFileAsync(FileMirrorRequest request, CancellationToken ct)
    {
        if (!RemoteFileNameValidator.TryValidateSegment(request.Filename, out var reason))
        {
            return Fail(FileTransferErrorCode.PathInvalid, reason);
        }
        if (!RemotePathValidator.TryResolve(_root, request.TargetDir, out var dirPath, out var pathError))
        {
            return Fail(pathError.Code, pathError.Message);
        }
        if (!Directory.Exists(dirPath))
        {
            return Fail(FileTransferErrorCode.PathNotFound, $"no such directory: {request.TargetDir}");
        }

        var targetPath = Path.Combine(dirPath, request.Filename);
        var tmpPath = targetPath + ".downloading";
        try
        {
            using var resp = await _httpClient.GetAsync(request.DownloadUrl, HttpCompletionOption.ResponseHeadersRead, ct);
            resp.EnsureSuccessStatusCode();

            await using (var fileStream = File.Create(tmpPath))
            {
                await resp.Content.CopyToAsync(fileStream, ct);
            }

            var actual = await ComputeSha256Async(tmpPath, ct);
            if (!string.Equals(actual, request.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                _logger.LogError("Mirror {RequestId} sha256 mismatch for {Filename}: expected {Expected}, got {Actual}.",
                    request.RequestId, request.Filename, request.Sha256, actual);
                File.Delete(tmpPath);
                return Fail(FileTransferErrorCode.ShaMismatch, "uploaded content does not match its sha256");
            }

            File.Move(tmpPath, targetPath, overwrite: true);
            _logger.LogInformation("Mirror {RequestId} wrote {Filename} into {Dir} ({Size} bytes).",
                request.RequestId, request.Filename, request.TargetDir, request.SizeBytes);
            return new FileOperationAck(Success: true, Error: null);
        }
        catch (OperationCanceledException)
        {
            CleanupTmp(tmpPath);
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Mirror {RequestId} failed to write {Filename}.", request.RequestId, request.Filename);
            CleanupTmp(tmpPath);
            return Fail(FileTransferErrorCode.TransferFailed, ex.Message);
        }
    }

    /// <summary>
    /// Validate a phone download synchronously, then push the file to S3 in the background
    /// and report completion through "CompleteFileTransfer".
    /// </summary>
    public Task<FileOperationAck> HandleBeginFileUploadAsync(BeginFileUploadRequest request, CancellationToken ct)
    {
        if (!RemotePathValidator.TryResolve(_root, request.Path, out var filePath, out var pathError))
        {
            return Task.FromResult(Fail(pathError.Code, pathError.Message));
        }
        if (Directory.Exists(filePath))
        {
            return Task.FromResult(Fail(FileTransferErrorCode.NotADirectory, $"path is a directory: {request.Path}"));
        }
        if (!File.Exists(filePath))
        {
            return Task.FromResult(Fail(FileTransferErrorCode.FileNotFound, $"no such file: {request.Path}"));
        }

        var size = new FileInfo(filePath).Length;
        if (size > _maxTransferBytes)
        {
            return Task.FromResult(Fail(FileTransferErrorCode.FileTooLarge,
                $"file exceeds the {_maxTransferBytes / (1024 * 1024)} MB transfer limit"));
        }

        _ = UploadPipelineAsync(request.RequestId, filePath, size);
        return Task.FromResult(new FileOperationAck(Success: true, Error: null));
    }

    /// <summary>
    /// sha → presigned PUT → stream upload → complete. Failures are reported to the Gateway
    /// so the phone's poll sees a terminal failed state instead of hanging.
    /// </summary>
    private async Task UploadPipelineAsync(string requestId, string filePath, long size)
    {
        await _uploadSlots.WaitAsync();
        try
        {
            var sha = await ComputeSha256Async(filePath, CancellationToken.None);
            var upload = await _gatewayClient.RequestFileUploadUrlAsync(
                new FileUploadUrlRequest(requestId, size, sha), CancellationToken.None);

            var content = new ByteArrayContent(await File.ReadAllBytesAsync(filePath));
            content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/octet-stream");
            using (content)
            {
                using var resp = await _httpClient.PutAsync(upload.UploadUrl, content);
                resp.EnsureSuccessStatusCode();
            }

            await _gatewayClient.CompleteFileTransferAsync(
                new CompleteFileTransferRequest(requestId, Success: true, Error: null), CancellationToken.None);
            _logger.LogInformation("Transfer {RequestId} uploaded {Path} ({Size} bytes).", requestId, filePath, size);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Transfer {RequestId} upload of {Path} failed.", requestId, filePath);
            try
            {
                await _gatewayClient.CompleteFileTransferAsync(
                    new CompleteFileTransferRequest(requestId, Success: false, Error: ex.Message), CancellationToken.None);
            }
            catch (Exception reportEx)
            {
                _logger.LogError(reportEx, "Transfer {RequestId} failed to report its failure.", requestId);
            }
        }
        finally
        {
            _uploadSlots.Release();
        }
    }

    private static void CleanupTmp(string tmpPath)
    {
        try { if (File.Exists(tmpPath)) File.Delete(tmpPath); }
        catch (IOException) { }
    }

    private static FileOperationAck Fail(string code, string message)
        => new(Success: false, Error: new FileOperationError(code, message));

    public static async Task<string> ComputeSha256Async(string path, CancellationToken ct)
    {
        await using var stream = File.OpenRead(path);
        using var sha = SHA256.Create();
        var hash = await sha.ComputeHashAsync(stream, ct);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}
