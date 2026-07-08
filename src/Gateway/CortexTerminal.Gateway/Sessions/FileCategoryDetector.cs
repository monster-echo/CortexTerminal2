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
