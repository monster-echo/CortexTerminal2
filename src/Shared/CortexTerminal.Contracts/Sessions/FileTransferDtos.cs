using MessagePack;

namespace CortexTerminal.Contracts.Sessions;

/// <summary>
/// Remote file browsing: one directory of the Worker's session root (the PTY cwd,
/// the user's home). Entries are the raw filesystem listing, dotfiles included.
/// </summary>
[MessagePackObject]
public sealed record FileEntry(
    [property: Key(0)] string Name,
    [property: Key(1)] bool IsDirectory,
    [property: Key(2)] long SizeBytes,
    [property: Key(3)] DateTimeOffset? ModifiedUtc);

[MessagePackObject]
public sealed record FileListing(
    [property: Key(0)] string Path,
    [property: Key(1)] IReadOnlyList<FileEntry> Entries,
    [property: Key(2)] bool Truncated);

[MessagePackObject]
public sealed record FileOperationError(
    [property: Key(0)] string Code,
    [property: Key(1)] string Message);

/// <summary>
/// Result envelope for the Gateway→Worker "ListFiles" invoke: either a listing or a
/// structured error, never both. Keeps RPC failures out of the exception channel so the
/// phone always receives a mappable error code.
/// </summary>
[MessagePackObject]
public sealed record FileListingResult(
    [property: Key(0)] FileListing? Listing,
    [property: Key(1)] FileOperationError? Error);

[MessagePackObject]
public sealed record FileOperationAck(
    [property: Key(0)] bool Success,
    [property: Key(1)] FileOperationError? Error);

/// <summary>
/// Gateway→Worker command mirroring a phone upload: download the S3 object at
/// <see cref="DownloadUrl"/> (presigned GET) and write it to TargetDir/Filename.
/// </summary>
[MessagePackObject]
public sealed record FileMirrorRequest(
    [property: Key(0)] string RequestId,
    [property: Key(1)] string TargetDir,
    [property: Key(2)] string Filename,
    [property: Key(3)] long SizeBytes,
    [property: Key(4)] string Sha256,
    [property: Key(5)] string DownloadUrl);

/// <summary>
/// Gateway→Worker command starting a phone download: validate the file at Path, then
/// push it to S3 and report back via "CompleteFileTransfer".
/// </summary>
[MessagePackObject]
public sealed record BeginFileUploadRequest(
    [property: Key(0)] string RequestId,
    [property: Key(1)] string Path,
    [property: Key(2)] long SizeBytes);

/// <summary>Worker→Gateway RPC: request a presigned PUT for a transfer object.</summary>
[MessagePackObject]
public sealed record FileUploadUrlRequest(
    [property: Key(0)] string RequestId,
    [property: Key(1)] long SizeBytes,
    [property: Key(2)] string Sha256);

[MessagePackObject]
public sealed record TransferUploadUrlResponse(
    [property: Key(0)] string UploadUrl,
    [property: Key(1)] DateTimeOffset ExpiresAt);

/// <summary>Worker→Gateway notification: a transfer upload finished (or failed).</summary>
[MessagePackObject]
public sealed record CompleteFileTransferRequest(
    [property: Key(0)] string RequestId,
    [property: Key(1)] bool Success,
    [property: Key(2)] string? Error);

public static class FileTransferStatus
{
    public const string Pending = "pending";
    public const string Ready = "ready";
    public const string Failed = "failed";
}

public static class FileTransferErrorCode
{
    public const string PathInvalid = "path_invalid";
    public const string PathNotFound = "path_not_found";
    public const string NotADirectory = "not_a_directory";
    public const string AccessDenied = "access_denied";
    public const string FileNotFound = "file_not_found";
    public const string FileTooLarge = "file_too_large";
    public const string TooManyEntries = "too_many_entries";
    public const string ShaMismatch = "sha_mismatch";
    public const string TransferNotFound = "transfer_not_found";
    public const string TransferFailed = "transfer_failed";
    public const string Timeout = "timeout";
}
