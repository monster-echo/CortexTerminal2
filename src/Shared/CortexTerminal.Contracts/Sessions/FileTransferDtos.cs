using MessagePack;

namespace CortexTerminal.Contracts.Sessions;

/// <summary>
/// Remote file browsing: one directory of a workspace on the Worker. Entries are the raw
/// filesystem listing, dotfiles included.
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

/// <summary>
/// Result envelope for the Gateway→Worker file mutation invokes ("Mkdir" /
/// "WriteTextFile" / "Rename" / "Delete"): a null Error means the operation succeeded.
/// Same shape philosophy as <see cref="FileListingResult"/> — structured failures travel
/// in-band so the phone always receives a mappable error code.
/// </summary>
[MessagePackObject]
public sealed record FileOpResult(
    [property: Key(0)] FileOperationError? Error);

[MessagePackObject]
public sealed record FileOperationAck(
    [property: Key(0)] bool Success,
    [property: Key(1)] FileOperationError? Error);

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
    public const string WorkerOffline = "worker_offline";
}
