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

        // No trimming: the path must resolve exactly as the browser saw it. A file literally
        // named "note " is legal on Unix; silently stripping its space would break the link
        // between the listing and the filesystem.
        var raw = relativePath ?? "";
        if (raw.Length > MaxPathLength)
        {
            error = Invalid("path exceeds 1024 characters");
            return false;
        }

        if (raw is "" or ".")
        {
            return true;
        }

        var normalized = raw.Replace('\\', '/');
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

        // 产品决策：符号链接一律跟随（用户建链接就是为了让它出现在那里），
        // 不做逃逸检查；断链交给下游的 Existence 判断自然报 not found。
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
