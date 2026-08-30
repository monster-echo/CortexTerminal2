using System.Diagnostics.CodeAnalysis;
using CortexTerminal.Contracts.Sessions;

namespace CortexTerminal.Worker.RemoteFiles;

/// <summary>
/// Resolves a phone-supplied relative path against the session root (the PTY cwd, the
/// user's home) and refuses anything that escapes it — lexical traversal and symlinks
/// alike. The root is fixed: it does not follow the shell's <c>cd</c>.
/// </summary>
public static class RemotePathValidator
{
    public const int MaxPathDepth = 32;
    public const int MaxPathLength = 1024;

    /// <summary>
    /// Resolve <paramref name="relativePath"/> ("" or "." is the root itself) to an
    /// absolute path. On success returns true and <paramref name="fullPath"/> is guaranteed
    /// to stay inside <paramref name="root"/>, following every symlink to its final target.
    /// On failure returns false with a structured <paramref name="error"/>.
    /// </summary>
    public static bool TryResolve(
        string root,
        string? relativePath,
        out string fullPath,
        [NotNullWhen(false)] out FileOperationError? error)
    {
        fullPath = root;
        error = null;

        var trimmed = relativePath?.Trim() ?? "";
        if (trimmed.Length > MaxPathLength)
        {
            error = Invalid("path exceeds 1024 characters");
            return false;
        }

        if (trimmed is "" or ".")
        {
            return true;
        }

        var normalized = trimmed.Replace('\\', '/');
        if (Path.IsPathRooted(normalized))
        {
            error = Invalid("absolute paths are not allowed");
            return false;
        }

        var segments = normalized.Split('/');
        if (segments.Length > MaxPathDepth)
        {
            error = Invalid($"path exceeds {MaxPathDepth} segments");
            return false;
        }

        foreach (var segment in segments)
        {
            if (segment is "" or ".")
            {
                error = Invalid("empty or '.' path segment");
                return false;
            }
            if (!RemoteFileNameValidator.TryValidateSegment(segment, out var reason))
            {
                error = Invalid(reason);
                return false;
            }
        }

        var candidate = Path.GetFullPath(Path.Combine(new[] { root }.Concat(segments).ToArray()));
        if (!IsInsideRoot(root, candidate))
        {
            error = Invalid("resolved path escapes the session root");
            return false;
        }

        // Symlink escape check: walk each level; if the entry is a link, its FINAL target
        // must still resolve inside the root. A broken link is rejected as not found — the
        // caller asked for a real entry.
        var current = root;
        foreach (var segment in segments)
        {
            current = Path.Combine(current, segment);
            var info = Stat(current);
            var linkTarget = info.LinkTarget;
            if (linkTarget is null)
            {
                continue;
            }

            var final = info.ResolveLinkTarget(returnFinalTarget: true)?.FullName;
            if (final is null)
            {
                error = new FileOperationError(FileTransferErrorCode.PathNotFound, $"broken symlink: {relativePath}");
                return false;
            }
            var resolved = Path.GetFullPath(final);
            if (!IsInsideRoot(root, resolved))
            {
                error = Invalid($"symlink escapes the session root: {segment}");
                return false;
            }
        }

        fullPath = candidate;
        return true;
    }

    public static bool IsInsideRoot(string root, string candidate)
    {
        var separator = Path.DirectorySeparatorChar;
        return candidate == root || candidate.StartsWith(root + separator, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);
    }

    private static FileOperationError Invalid(string message)
        => new(FileTransferErrorCode.PathInvalid, message);

    /// <summary>
    /// One stat path for both files and directories — <see cref="FileSystemInfo.LinkTarget"/>
    /// and <see cref="FileSystemInfo.ResolveLinkTarget(bool)"/> live on the base class.
    /// </summary>
    private static FileSystemInfo Stat(string path)
        => Directory.Exists(path) ? new DirectoryInfo(path) : new FileInfo(path);
}
