using CortexTerminal.Contracts.Sessions;

namespace CortexTerminal.Worker.RemoteFiles;

/// <summary>
/// Lists one directory of the session root for the phone's file browser. Returns the raw
/// filesystem view — dotfiles included — directories first, then by name.
/// </summary>
public sealed class RemoteDirectoryLister(string root, int maxEntries)
{
    /// <summary>
    /// List <paramref name="relativePath"/>. Never throws for expected failure modes —
    /// invalid paths, missing targets and permission problems all come back as a
    /// structured <see cref="FileOperationError"/> so the phone can render them.
    /// </summary>
    public FileListingResult List(string? relativePath)
    {
        if (!RemotePathValidator.TryResolve(root, relativePath, out var fullPath, out var error))
        {
            return new FileListingResult(Listing: null, Error: error);
        }

        if (!Directory.Exists(fullPath))
        {
            var code = File.Exists(fullPath)
                ? FileTransferErrorCode.NotADirectory
                : FileTransferErrorCode.PathNotFound;
            return new FileListingResult(null, new FileOperationError(code, $"no such directory: {relativePath}"));
        }

        FileSystemInfo[] entries;
        try
        {
            entries = new DirectoryInfo(fullPath)
                .EnumerateFileSystemInfos()
                .ToArray();
        }
        catch (Exception ex) when (ex is DirectoryNotFoundException or FileNotFoundException)
        {
            return new FileListingResult(null, new FileOperationError(FileTransferErrorCode.PathNotFound, $"no such directory: {relativePath}"));
        }
        catch (UnauthorizedAccessException ex)
        {
            return new FileListingResult(null, new FileOperationError(FileTransferErrorCode.AccessDenied, ex.Message));
        }

        // 产品决策：符号链接跟随展示（含指向根外部的链接）。
        var ordered = entries
            .OrderBy(e => e is DirectoryInfo ? 0 : 1)
            .ThenBy(e => e.Name, StringComparer.Ordinal)
            .ToArray();

        var truncated = ordered.Length > maxEntries;
        var mapped = ordered
            .Take(maxEntries)
            .Select(e => new FileEntry(
                Name: e.Name,
                IsDirectory: e is DirectoryInfo,
                SizeBytes: e is FileInfo file ? file.Length : 0,
                ModifiedUtc: new DateTimeOffset(e.LastWriteTimeUtc)))
            .ToArray();

        return new FileListingResult(
            Listing: new FileListing(relativePath ?? "", mapped, truncated),
            Error: null);
    }
}
