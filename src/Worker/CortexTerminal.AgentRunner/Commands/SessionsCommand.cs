using System.Text.Json.Nodes;
using CortexTerminal.AgentRunner.Logging;

namespace CortexTerminal.AgentRunner.Commands;

/// <summary>
/// <c>cortap sessions [--json]</c> — list all sessions on disk, newest first. Output columns:
/// SESSION_ID, KIND, STARTED, EVENTS, STATUS, CWD. Active sessions are marked with "*";
/// crashed sessions (process died without writing endedAt, then reaped) are marked "!".
///
/// <para>With <c>--json</c>, emits a JSON array on stdout: each session is
/// {sessionId, kind, cwd, startedAt, endedAt, pid, eventCount, lastEventAt, isActive, isCrashed}.</para>
/// </summary>
internal static class SessionsCommand
{
    public static int Run(string[] args)
    {
        var json = Array.IndexOf(args, "--json") >= 0;
        var sessions = SessionStore.EnumerateSessions().OrderByDescending(s => s.StartedAt ?? DateTimeOffset.MinValue).ToList();

        if (json)
        {
            Console.Out.WriteLine(BuildJson(sessions).ToJsonString());
            return 0;
        }

        if (sessions.Count == 0)
        {
            Console.Out.WriteLine("No sessions found. Run `cortap claude` to start one.");
            return 0;
        }

        Console.Out.WriteLine($"{"SESSION_ID",-16} {"KIND",-12} {"STARTED",-20} {"EVT",4} {"ST",-2} CWD");
        foreach (var s in sessions)
        {
            var started = s.StartedAt?.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss") ?? "?";
            var status = s.IsActive ? "* " :
                         s.EndedAt is null ? "? " :
                         "  ";
            var cwd = ShortenCwd(s.Cwd);
            Console.Out.WriteLine($"{s.SessionId,-16} {s.Kind,-12} {started,-20} {s.EventCount,4} {status} {cwd}");
        }

        Console.Out.WriteLine();
        Console.Out.WriteLine($"Total: {sessions.Count} session(s), {sessions.Count(s => s.IsActive)} active.");
        return 0;
    }

    internal static JsonArray BuildJson(IEnumerable<SessionInfo> sessions)
    {
        var arr = new JsonArray();
        foreach (var s in sessions)
        {
            // Cast to JsonNode so we hit the non-generic Add(JsonNode) overload — the generic
            // Add<T>(T) is flagged IL2026/IL3050 under AOT (creating JsonValue from arbitrary
            // types needs runtime codegen).
            arr.Add((JsonNode)new JsonObject
            {
                ["sessionId"] = s.SessionId,
                ["kind"] = s.Kind,
                ["cwd"] = s.Cwd,
                ["startedAt"] = ToIso(s.StartedAt),
                ["endedAt"] = ToIso(s.EndedAt),
                ["pid"] = s.Pid,
                ["eventCount"] = s.EventCount,
                ["lastEventAt"] = ToIso(s.LastEventAt),
                ["isActive"] = s.IsActive,
                ["isCrashed"] = !s.IsActive && s.EndedAt is null,
            });
        }
        return arr;
    }

    private static string? ToIso(DateTimeOffset? d)
        => d?.ToString("O", System.Globalization.CultureInfo.InvariantCulture);

    private static string ShortenCwd(string cwd)
    {
        if (string.IsNullOrEmpty(cwd)) return "?";
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (cwd.StartsWith(home, StringComparison.Ordinal))
        {
            return "~" + cwd[home.Length..];
        }
        return cwd;
    }
}
