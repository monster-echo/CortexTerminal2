namespace CortexTerminal.Worker.Artifacts;

/// <summary>
/// Resolves artifact directory locations for each session. Layout:
/// <c>~/.corterm/sessions/{sessionId}/artifacts/</c>. The path is exposed to the PTY via the
/// <c>CORTERM_ARTIFACTS_DIR</c> env var so AI agents (e.g. Claude Code) can write progress files
/// that the user will see in their console's file feed.
/// </summary>
public static class ArtifactPaths
{
    public static string GetSessionsRoot()
    {
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return Path.Combine(profile, ".corterm", "sessions");
    }

    public static string GetSessionArtifactsDir(string sessionId)
        => Path.Combine(GetSessionsRoot(), sessionId, "artifacts");

    public static string GetSessionDir(string sessionId)
        => Path.Combine(GetSessionsRoot(), sessionId);

    public static void EnsureSessionArtifactsDir(string sessionId)
    {
        var dir = GetSessionArtifactsDir(sessionId);
        Directory.CreateDirectory(dir);
    }

    public static void DeleteSessionDir(string sessionId)
    {
        var dir = GetSessionDir(sessionId);
        if (!Directory.Exists(dir)) return;
        try { Directory.Delete(dir, recursive: true); }
        catch (IOException) { /* best-effort cleanup */ }
        catch (UnauthorizedAccessException) { /* best-effort cleanup */ }
    }
}
