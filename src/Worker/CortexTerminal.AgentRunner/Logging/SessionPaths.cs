namespace CortexTerminal.AgentRunner.Logging;

/// <summary>
/// Filesystem layout for cortap session logs. Layout (under user home):
///
/// <code>
/// ~/.corterm/sessions/
///   &lt;sessionId&gt;/
///     meta.json     — session metadata (kind, cwd, startedAt, endedAt?, pid, ...)
///     events.jsonl  — one JSON object per line, each hook event
///     pid           — cortap main process PID (deleted on clean exit)
/// </code>
///
/// Path resolution respects <paramref name="home"/> only for tests — production code should
/// always resolve against <c>UserProfile</c> so the worker and the agent binary agree on the
/// root even when invoked with different working directories.
/// </summary>
internal static class SessionPaths
{
    public static string GetSessionsRoot(string? home = null)
    {
        home ??= Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return Path.Combine(home, ".corterm", "sessions");
    }

    public static string GetSessionDir(string sessionId, string? home = null)
        => Path.Combine(GetSessionsRoot(home), sessionId);

    public static string GetEventsPath(string sessionId, string? home = null)
        => Path.Combine(GetSessionDir(sessionId, home), "events.jsonl");

    public static string GetMetaPath(string sessionId, string? home = null)
        => Path.Combine(GetSessionDir(sessionId, home), "meta.json");

    public static string GetPidPath(string sessionId, string? home = null)
        => Path.Combine(GetSessionDir(sessionId, home), "pid");
}
