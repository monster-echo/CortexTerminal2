using System.Text.RegularExpressions;

namespace CortexTerminal.Contracts.Sessions;

/// <summary>
/// Filename safety check shared by Gateway (upload ingress) and Worker (download mirror).
/// Uses a blacklist: forbids path separators, control chars, null bytes, leading/trailing
/// dots/spaces, Windows reserved names, and dot-segment traversal. Allows Unicode
/// letters/digits, interior spaces, and common punctuation so real-world filenames like
/// "屏幕截图 2026.png" or "Screenshot (1).png" work.
/// </summary>
/// <remarks>
/// MUST stay in this shared contract. A previous divergent copy in the Worker used an
/// ASCII-only whitelist that silently rejected non-ASCII filenames (e.g. Chinese); keeping a
/// single source prevents that drift from recurring.
/// </remarks>
public static class ArtifactFilenameValidator
{
    private static readonly Regex UnsafeChars = new(@"[\x00-\x1f/\\:<>|?*""]", RegexOptions.Compiled);
    private static readonly Regex DotTraversal = new(@"\.\.", RegexOptions.Compiled);
    private static readonly Regex EdgeDotOrSpace = new(@"^[. ]|[. ]$", RegexOptions.Compiled);
    private static readonly Regex WindowsReserved = new(@"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static bool IsValid(string filename) => TryValidate(filename, out _);

    /// <summary>
    /// Validates <paramref name="filename"/> and, on failure, sets <paramref name="reason"/>
    /// to an English description of the first failing rule. Kept English on purpose so log /
    /// console encoding cannot garble the diagnostic.
    /// </summary>
    public static bool TryValidate(string filename, out string reason)
    {
        if (string.IsNullOrWhiteSpace(filename)) { reason = "filename is empty or whitespace"; return false; }
        if (filename.Length > 255) { reason = "filename exceeds 255 characters"; return false; }
        if (UnsafeChars.IsMatch(filename)) { reason = "filename contains forbidden characters (control chars or one of / \\ : < > | ? * \")"; return false; }
        if (DotTraversal.IsMatch(filename)) { reason = "filename contains '..'"; return false; }
        if (EdgeDotOrSpace.IsMatch(filename)) { reason = "filename starts or ends with '.' or space"; return false; }
        if (WindowsReserved.IsMatch(filename)) { reason = "filename is a Windows reserved name (CON, PRN, AUX, NUL, COM1-9, LPT1-9)"; return false; }
        reason = "";
        return true;
    }
}
