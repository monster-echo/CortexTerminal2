using CortexTerminal.AgentRunner.Logging;

namespace CortexTerminal.AgentRunner.Commands;

/// <summary>
/// <c>cortap tail [sessionId] [--all] [--latest] [--current] [--no-follow]</c> —
/// follow events.jsonl in real time.
///
/// <para>Default behavior depends on the number of active sessions:</para>
/// <list type="bullet">
/// <item>0 active → error with hint.</item>
/// <item>1 active → follow it automatically.</item>
/// <item>2+ active → list them and ask the user to specify.</item>
/// </list>
/// </summary>
internal static class TailCommand
{
    public static int Run(string[] args)
    {
        var argList = args.ToList();
        var follow = !argList.Remove("--no-follow");
        var all = argList.Remove("--all");
        var latest = argList.Remove("--latest");
        var current = argList.Remove("--current");
        string? explicitSession = argList.FirstOrDefault();

        if (current)
        {
            explicitSession = Environment.GetEnvironmentVariable("CORTERM_SESSION_ID");
            if (string.IsNullOrEmpty(explicitSession))
            {
                Console.Error.WriteLine("cortap tail: --current requires CORTERM_SESSION_ID (run inside a cortap session).");
                return 1;
            }
        }

        var activeSessions = SessionStore.EnumerateSessions().Where(s => s.IsActive).ToList();

        List<SessionInfo> targets;
        if (all)
        {
            targets = activeSessions;
            if (targets.Count == 0)
            {
                Console.Error.WriteLine("cortap tail: no active sessions to follow.");
                Console.Error.WriteLine("  Start one with: cortap claude");
                return 1;
            }
        }
        else if (explicitSession is not null)
        {
            var s = SessionStore.TryGetSession(explicitSession);
            if (s is null)
            {
                Console.Error.WriteLine($"cortap tail: session '{explicitSession}' not found.");
                return 1;
            }
            targets = new List<SessionInfo> { s };
        }
        else if (latest)
        {
            var s = activeSessions.OrderByDescending(x => x.StartedAt ?? DateTimeOffset.MinValue).FirstOrDefault();
            if (s is null)
            {
                Console.Error.WriteLine("cortap tail: no active sessions.");
                return 1;
            }
            targets = new List<SessionInfo> { s };
        }
        else
        {
            switch (activeSessions.Count)
            {
                case 0:
                    Console.Error.WriteLine("cortap tail: no active sessions.");
                    Console.Error.WriteLine("  Start one with: cortap claude");
                    return 1;
                case 1:
                    targets = activeSessions;
                    break;
                default:
                    Console.Error.WriteLine("Multiple active sessions:");
                    foreach (var si in activeSessions)
                    {
                        var started = si.StartedAt?.LocalDateTime.ToString("HH:mm:ss") ?? "?";
                        Console.Error.WriteLine($"  {si.SessionId}  started {started}  {si.Kind}  cwd={si.Cwd}");
                    }
                    Console.Error.WriteLine();
                    Console.Error.WriteLine("Use:");
                    Console.Error.WriteLine("  cortap tail <sessionId>    Follow a specific session");
                    Console.Error.WriteLine("  cortap tail --all          Merge all sessions (with prefix)");
                    Console.Error.WriteLine("  cortap tail --latest       Follow most recent");
                    return 1;
            }
        }

        var showPrefix = targets.Count > 1;
        foreach (var t in targets)
        {
            var started = t.StartedAt?.LocalDateTime.ToString("HH:mm:ss") ?? "?";
            Console.Error.WriteLine($"Following {t.SessionId} (started {started}, {t.Kind})");
        }

        if (!follow)
        {
            foreach (var t in targets)
            {
                DumpAll(t.SessionId, showPrefix);
            }
            return 0;
        }

        return FollowTargets(targets, showPrefix);
    }

    private static void DumpAll(string sessionId, bool showPrefix)
    {
        var eventsPath = SessionPaths.GetEventsPath(sessionId);
        if (!File.Exists(eventsPath)) return;

        try
        {
            using var fs = new FileStream(eventsPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var reader = new StreamReader(fs);
            string? line;
            while ((line = reader.ReadLine()) is not null)
            {
                OutputLine(line, sessionId, showPrefix);
            }
        }
        catch (IOException) { }
    }

    private static int FollowTargets(List<SessionInfo> targets, bool showPrefix)
    {
        var positions = targets.ToDictionary(t => t.SessionId, _ => 0L);
        var sessionIds = positions.Keys.ToList();
        foreach (var sessionId in sessionIds)
        {
            var pos = positions[sessionId];
            DumpFrom(sessionId, ref pos, showPrefix);
            positions[sessionId] = pos;
        }

        var cts = new CancellationTokenSource();
        Console.CancelKeyPress += (_, e) => { e.Cancel = true; cts.Cancel(); };

        while (!cts.IsCancellationRequested)
        {
            Thread.Sleep(200);
            foreach (var sessionId in sessionIds)
            {
                var pos = positions[sessionId];
                DumpFrom(sessionId, ref pos, showPrefix);
                positions[sessionId] = pos;
            }
        }

        Console.Error.WriteLine("\nstopped.");
        return 0;
    }

    private static void DumpFrom(string sessionId, ref long position, bool showPrefix)
    {
        var eventsPath = SessionPaths.GetEventsPath(sessionId);
        if (!File.Exists(eventsPath)) return;

        try
        {
            using var fs = new FileStream(eventsPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            if (fs.Length < position) position = 0;
            fs.Seek(position, SeekOrigin.Begin);
            using var reader = new StreamReader(fs);
            string? line;
            while ((line = reader.ReadLine()) is not null)
            {
                OutputLine(line, sessionId, showPrefix);
            }
            position = fs.Position;
        }
        catch (IOException) { }
    }

    private static void OutputLine(string jsonLine, string sessionId, bool showPrefix)
    {
        var rendered = EventFormatter.Format(jsonLine);
        if (showPrefix)
        {
            var prefix = sessionId.Length >= 8 ? sessionId[..8] : sessionId;
            Console.Out.WriteLine($"[{prefix}] {rendered}");
        }
        else
        {
            Console.Out.WriteLine(rendered);
        }
    }
}
