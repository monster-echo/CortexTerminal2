using CortexTerminal.Mobile.Core.Bridge;

namespace CortexTerminal.Mobile.App.Services.Bridge;

/// <summary>
/// Device-side persistence of xterm scrollback snapshots.
///
/// The web layer serializes the terminal (screen + scrollback) with
/// @xterm/addon-serialize and pushes it here in base64 chunks — a full 64k-line
/// serialization is multi-MB, too big for a single bridge invoke. Chunks append
/// to a temp file and the last chunk renames it into place, so an interrupted
/// save never leaves a corrupt snapshot. Restores go back to JS through the
/// registered-web-file route (RegisterWebFile) instead of the JSON invoke
/// channel for the same size reason.
/// </summary>
public sealed partial class AppBridge
{
    private const int SnapshotPruneKeep = 10;

    private static string SnapshotsDir => Path.Combine(FileSystem.AppDataDirectory, "terminal_snapshots");

    [BridgeMethod]
    public Task<string> SaveTerminalSnapshotChunkAsync(string sessionId, int seq, int total, string base64Chunk)
    {
        return ExecuteSafeVoidAsync(() =>
        {
            var safeName = SanitizeSessionId(sessionId);
            if (total <= 0)
            {
                throw new ArgumentOutOfRangeException(nameof(total), "Snapshot chunk total must be positive.");
            }
            if (seq < 0 || seq >= total)
            {
                throw new ArgumentOutOfRangeException(nameof(seq), $"Snapshot chunk index {seq} out of range (total {total}).");
            }

            var directory = SnapshotsDir;
            Directory.CreateDirectory(directory);
            var finalPath = Path.Combine(directory, safeName + ".txt");
            var tempPath = finalPath + ".tmp";
            var bytes = Convert.FromBase64String(base64Chunk);

            using (var stream = new FileStream(
                tempPath,
                seq == 0 ? FileMode.Create : FileMode.Append,
                FileAccess.Write,
                FileShare.None))
            {
                stream.Write(bytes);
            }

            if (seq == total - 1)
            {
                File.Move(tempPath, finalPath, overwrite: true);
                PruneSnapshots(directory);
            }

            return Task.CompletedTask;
        });
    }

    [BridgeMethod]
    public Task<string> GetTerminalSnapshotAsync(string sessionId)
    {
        return ExecuteSafeAsync(() =>
        {
            var path = Path.Combine(SnapshotsDir, SanitizeSessionId(sessionId) + ".txt");
            if (!File.Exists(path))
            {
                return Task.FromResult(new TerminalSnapshotInfo(false, 0, null));
            }

            var url = RegisterWebFile(path, "text/plain; charset=utf-8", "terminal-snapshot.txt");
            return Task.FromResult(new TerminalSnapshotInfo(true, new FileInfo(path).Length, url));
        });
    }

    [BridgeMethod]
    public Task<string> DeleteTerminalSnapshotAsync(string sessionId)
    {
        return ExecuteSafeVoidAsync(() =>
        {
            var path = Path.Combine(SnapshotsDir, SanitizeSessionId(sessionId) + ".txt");
            if (File.Exists(path))
            {
                File.Delete(path);
            }

            return Task.CompletedTask;
        });
    }

    private static string SanitizeSessionId(string sessionId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sessionId);
        foreach (var c in sessionId)
        {
            if (!char.IsAsciiLetterOrDigit(c) && c != '-' && c != '_')
            {
                throw new ArgumentException($"Session id contains invalid character '{c}'.");
            }
        }

        return sessionId;
    }

    private static void PruneSnapshots(string directory)
    {
        var files = Directory.GetFiles(directory, "*.txt")
            .Select(path => new FileInfo(path))
            .OrderByDescending(info => info.LastWriteTimeUtc)
            .ToList();

        foreach ( var stale in files.Skip(SnapshotPruneKeep))
        {
            stale.Delete();
        }
    }

    public sealed record TerminalSnapshotInfo(bool Exists, long Size, string? Url);
}
