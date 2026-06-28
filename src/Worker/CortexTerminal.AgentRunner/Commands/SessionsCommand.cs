using CortexTerminal.AgentRunner.Logging;

namespace CortexTerminal.AgentRunner.Commands;

/// <summary>
/// <c>cortap sessions</c> — list all sessions on disk, newest first. Output columns:
/// SESSION_ID, KIND, STARTED, EVENTS, STATUS, CWD. Active sessions are marked with "*";
/// crashed sessions (process died without writing endedAt, then reaped) are marked "!".
/// </summary>
internal static class SessionsCommand
{
    public static int Run(string[] args)
    {
        var sessions = SessionStore.EnumerateSessions().OrderByDescending(s => s.StartedAt ?? DateTimeOffset.MinValue).ToList();

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
