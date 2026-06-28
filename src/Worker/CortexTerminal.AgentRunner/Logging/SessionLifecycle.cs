using System.Text.Json.Nodes;

namespace CortexTerminal.AgentRunner.Logging;

/// <summary>
/// Owns the <c>meta.json</c> + <c>pid</c> files for a session. Created by the cortap
/// main process (the one that spawns the real agent binary) and disposed when that process
/// exits. Hook subprocesses (<c>cortap hook</c>) do NOT use this class — they write to
/// <c>events.jsonl</c> directly via <see cref="Sinks.FileSink"/>.
///
/// <para>
/// Crash safety: if the main process is killed (SIGKILL / kill -9), the <c>pid</c> file is
/// left behind pointing at a dead PID. <see cref="ReapOrphanedSessions"/> scans for these on
/// next startup and marks them as crashed.
/// </para>
/// </summary>
internal sealed class SessionLifecycle : IDisposable
{
    private readonly string _sessionId;
    private readonly string _kind;
    private readonly string _cwd;
    private readonly string _home;
    private readonly string _metaPath;
    private readonly string _pidPath;
    private readonly string _sessionDir;
    private bool _stopped;

    public SessionLifecycle(string sessionId, string kind, string cwd, string? home = null)
    {
        if (string.IsNullOrEmpty(sessionId)) throw new ArgumentException("sessionId must not be empty", nameof(sessionId));
        if (string.IsNullOrEmpty(kind)) throw new ArgumentException("kind must not be empty", nameof(kind));
        _sessionId = sessionId;
        _kind = kind;
        _cwd = cwd;
        _home = home ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        _sessionDir = SessionPaths.GetSessionDir(sessionId, _home);
        _metaPath = SessionPaths.GetMetaPath(sessionId, _home);
        _pidPath = SessionPaths.GetPidPath(sessionId, _home);
    }

    public string SessionId => _sessionId;
    public string SessionDir => _sessionDir;

    public void Start()
    {
        Directory.CreateDirectory(_sessionDir);
        var meta = new JsonObject
        {
            ["sessionId"] = _sessionId,
            ["kind"] = _kind,
            ["cwd"] = _cwd,
            ["startedAt"] = DateTimeOffset.UtcNow.ToString("O"),
            ["pid"] = Environment.ProcessId,
        };
        File.WriteAllText(_metaPath, meta.ToJsonString());
        File.WriteAllText(_pidPath, Environment.ProcessId.ToString());
    }

    public void Stop()
    {
        if (_stopped) return;
        _stopped = true;
        try
        {
            var content = File.ReadAllText(_metaPath);
            if (JsonNode.Parse(content) is JsonObject obj)
            {
                obj["endedAt"] = DateTimeOffset.UtcNow.ToString("O");
                File.WriteAllText(_metaPath, obj.ToJsonString());
            }
        }
        catch (FileNotFoundException)
        {
            // meta.json disappeared — nothing to update.
        }
        catch (IOException)
        {
            // Disk issue — best effort, don't crash the wrapper on cleanup.
        }
        try { File.Delete(_pidPath); } catch { }
    }

    public void Dispose() => Stop();

    /// <summary>
    /// Scan all session dirs, mark sessions whose <c>pid</c> is dead but missing
    /// <c>endedAt</c> as crashed. Called at cortap startup before any new session
    /// starts, so the listing commands don't show ghost sessions.
    /// </summary>
    public static int ReapOrphanedSessions(string? home = null)
    {
        var root = SessionPaths.GetSessionsRoot(home);
        if (!Directory.Exists(root)) return 0;

        var reaped = 0;
        foreach (var sessionDir in Directory.EnumerateDirectories(root))
        {
            var pidPath = Path.Combine(sessionDir, "pid");
            if (!File.Exists(pidPath)) continue;

            var metaPath = Path.Combine(sessionDir, "meta.json");
            if (!File.Exists(metaPath)) continue;

            if (HasEnded(metaPath)) continue;

            int pid;
            try { pid = int.Parse(File.ReadAllText(pidPath).Trim()); }
            catch (FormatException) { continue; }
            catch (IOException) { continue; }

            if (IsProcessAlive(pid)) continue;

            MarkCrashed(metaPath);
            try { File.Delete(pidPath); } catch { }
            reaped++;
        }
        return reaped;
    }

    private static bool HasEnded(string metaPath)
    {
        try
        {
            var content = File.ReadAllText(metaPath);
            return JsonNode.Parse(content) is JsonObject obj && obj.ContainsKey("endedAt");
        }
        catch { return false; }
    }

    private static void MarkCrashed(string metaPath)
    {
        try
        {
            var content = File.ReadAllText(metaPath);
            if (JsonNode.Parse(content) is JsonObject obj)
            {
                obj["endedAt"] = DateTimeOffset.UtcNow.ToString("O");
                obj["crashed"] = true;
                File.WriteAllText(metaPath, obj.ToJsonString());
            }
        }
        catch { }
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
            // Permission denied — assume alive to avoid false-positive cleanup.
            return true;
        }
    }
}
