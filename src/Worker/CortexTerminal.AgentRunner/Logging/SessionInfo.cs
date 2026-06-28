using System.Text.Json.Nodes;

namespace CortexTerminal.AgentRunner.Logging;

/// <summary>
/// Read-only view of a session, derived from <c>meta.json</c> + <c>events.jsonl</c> + <c>pid</c>.
/// Used by the listing / tail / events commands. <see cref="IsActive"/> reflects whether the
/// owning cortap main process is still alive (no <c>endedAt</c> and pid responds to
/// <c>kill -0</c>).
/// </summary>
internal sealed class SessionInfo
{
    public SessionInfo(
        string sessionId,
        string kind,
        string cwd,
        DateTimeOffset? startedAt,
        DateTimeOffset? endedAt,
        int? pid,
        long eventCount,
        DateTimeOffset? lastEventAt,
        bool isActive)
    {
        SessionId = sessionId;
        Kind = kind;
        Cwd = cwd;
        StartedAt = startedAt;
        EndedAt = endedAt;
        Pid = pid;
        EventCount = eventCount;
        LastEventAt = lastEventAt;
        IsActive = isActive;
    }

    public string SessionId { get; }
    public string Kind { get; }
    public string Cwd { get; }
    public DateTimeOffset? StartedAt { get; }
    public DateTimeOffset? EndedAt { get; }
    public int? Pid { get; }
    public long EventCount { get; }
    public DateTimeOffset? LastEventAt { get; }
    public bool IsActive { get; }
    public string SessionDir => SessionPaths.GetSessionDir(SessionId);
}

/// <summary>
/// Loading + listing logic for sessions on disk. Scans <c>~/.corterm/sessions/</c> and yields
/// <see cref="SessionInfo"/> records. Skips directories missing a valid <c>meta.json</c>.
/// </summary>
internal static class SessionStore
{
    public static IEnumerable<SessionInfo> EnumerateSessions(string? home = null)
    {
        var root = SessionPaths.GetSessionsRoot(home);
        if (!Directory.Exists(root)) yield break;

        foreach (var dir in Directory.EnumerateDirectories(root))
        {
            var info = TryReadSessionInfo(dir);
            if (info is not null) yield return info;
        }
    }

    public static SessionInfo? TryGetSession(string sessionId, string? home = null)
    {
        var dir = SessionPaths.GetSessionDir(sessionId, home);
        if (!Directory.Exists(dir)) return null;
        return TryReadSessionInfo(dir);
    }

    private static SessionInfo? TryReadSessionInfo(string sessionDir)
    {
        var metaPath = Path.Combine(sessionDir, "meta.json");
        if (!File.Exists(metaPath)) return null;

        JsonObject meta;
        try
        {
            if (JsonNode.Parse(File.ReadAllText(metaPath)) is not JsonObject obj) return null;
            meta = obj;
        }
        catch (IOException) { return null; }
        catch (ArgumentException) { return null; }

        var sessionId = meta["sessionId"]?.GetValue<string>() ?? Path.GetFileName(sessionDir);
        var kind = meta["kind"]?.GetValue<string>() ?? string.Empty;
        var cwd = meta["cwd"]?.GetValue<string>() ?? string.Empty;
        var startedAt = TryParseDate(meta["startedAt"]?.GetValue<string>());
        var endedAt = TryParseDate(meta["endedAt"]?.GetValue<string>());
        var pid = (int?)meta["pid"]?.GetValue<long>();

        var eventsPath = Path.Combine(sessionDir, "events.jsonl");
        var (eventCount, lastEventAt) = ReadEventStats(eventsPath);

        var isActive = endedAt is null && pid.HasValue && IsProcessAlive(pid.Value);

        return new SessionInfo(sessionId, kind, cwd, startedAt, endedAt, pid, eventCount, lastEventAt, isActive);
    }

    private static (long count, DateTimeOffset? lastAt) ReadEventStats(string eventsPath)
    {
        if (!File.Exists(eventsPath)) return (0, null);

        long count = 0;
        DateTimeOffset? lastAt = null;
        string? lastLine = null;

        try
        {
            using var fs = new FileStream(eventsPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var reader = new StreamReader(fs);
            string? line;
            while ((line = reader.ReadLine()) is not null)
            {
                count++;
                lastLine = line;
            }
        }
        catch (IOException) { return (count, lastAt); }

        if (lastLine is not null)
        {
            lastAt = ExtractTimestamp(lastLine);
        }

        return (count, lastAt);
    }

    private static DateTimeOffset? ExtractTimestamp(string jsonLine)
    {
        try
        {
            if (JsonNode.Parse(jsonLine) is JsonObject obj &&
                obj["ts"]?.GetValue<string>() is string ts)
            {
                return TryParseDate(ts);
            }
        }
        catch { }
        return null;
    }

    private static DateTimeOffset? TryParseDate(string? s)
    {
        if (string.IsNullOrEmpty(s)) return null;
        return DateTimeOffset.TryParse(s, out var d) ? d : null;
    }

    private static bool IsProcessAlive(int pid)
    {
        try
        {
            var probe = System.Diagnostics.Process.GetProcessById(pid);
            probe.Dispose();
            return true;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return true;
        }
    }
}
