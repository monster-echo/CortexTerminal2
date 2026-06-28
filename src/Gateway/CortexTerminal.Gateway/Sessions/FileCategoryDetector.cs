using System.Text.RegularExpressions;
using CortexTerminal.Contracts.Sessions;

namespace CortexTerminal.Gateway.Sessions;

/// <summary>
/// Classifies a filename into a coarse file category based on its extension.
/// Used for icon selection in the artifact feed UI across web and HarmonyOS.
/// </summary>
public static class FileCategoryDetector
{
    private static readonly HashSet<string> ImageExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg", ".ico", ".tiff", ".tif", ".heic"
    };

    private static readonly HashSet<string> PdfExtensions = new(StringComparer.OrdinalIgnoreCase) { ".pdf" };

    private static readonly HashSet<string> VideoExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".mp4", ".mov", ".mkv", ".webm", ".avi", ".flv", ".wmv", ".m4v", ".3gp"
    };

    private static readonly HashSet<string> AudioExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".mp3", ".wav", ".flac", ".aac", ".ogg", ".m4a", ".wma", ".opus"
    };

    private static readonly HashSet<string> ArchiveExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".zip", ".tar", ".gz", ".tgz", ".bz2", ".xz", ".7z", ".rar", ".zst"
    };

    private static readonly HashSet<string> CodeExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".cs", ".ts", ".tsx", ".js", ".jsx", ".py", ".go", ".rs", ".java", ".kt", ".swift",
        ".c", ".cpp", ".cc", ".h", ".hpp", ".rb", ".php", ".scala", ".lua", ".pl",
        ".sh", ".bash", ".zsh", ".fish", ".ps1", ".bat", ".cmd",
        ".sql", ".vue", ".svelte", ".html", ".css", ".scss", ".sass", ".less",
        ".json", ".yaml", ".yml", ".toml", ".xml", ".ini", ".conf", ".env"
    };

    private static readonly HashSet<string> TextExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".txt", ".md", ".markdown", ".rst", ".log", ".csv", ".tsv", ".rtf"
    };

    public static string Detect(string filename)
    {
        var ext = Path.GetExtension(filename);
        if (string.IsNullOrEmpty(ext)) return ArtifactFileCategory.Unknown;

        if (ImageExtensions.Contains(ext)) return ArtifactFileCategory.Image;
        if (PdfExtensions.Contains(ext)) return ArtifactFileCategory.Pdf;
        if (VideoExtensions.Contains(ext)) return ArtifactFileCategory.Video;
        if (AudioExtensions.Contains(ext)) return ArtifactFileCategory.Audio;
        if (ArchiveExtensions.Contains(ext)) return ArtifactFileCategory.Archive;
        if (CodeExtensions.Contains(ext)) return ArtifactFileCategory.Code;
        if (TextExtensions.Contains(ext)) return ArtifactFileCategory.Text;
        return ArtifactFileCategory.Unknown;
    }
}

/// <summary>
/// Filename safety check. Uses a blacklist: forbids path separators, control chars,
/// null bytes, leading/trailing dots/spaces, Windows reserved names, and dot-segment
/// traversal. Allows Unicode letters/digits, interior spaces, and common punctuation
/// so real-world filenames like "屏幕截图 2026.png" or "Screenshot (1).png" work.
/// </summary>
public static class ArtifactFilenameValidator
{
    private static readonly Regex UnsafeChars = new(@"[\x00-\x1f/\\:<>|?*""]", RegexOptions.Compiled);
    private static readonly Regex DotTraversal = new(@"\.\.", RegexOptions.Compiled);
    private static readonly Regex EdgeDotOrSpace = new(@"^[. ]|[. ]$", RegexOptions.Compiled);
    private static readonly Regex WindowsReserved = new(@"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static bool IsValid(string filename)
    {
        if (string.IsNullOrWhiteSpace(filename)) return false;
        if (filename.Length > 255) return false;
        if (UnsafeChars.IsMatch(filename)) return false;
        if (DotTraversal.IsMatch(filename)) return false;
        if (EdgeDotOrSpace.IsMatch(filename)) return false;
        if (WindowsReserved.IsMatch(filename)) return false;
        return true;
    }
}
