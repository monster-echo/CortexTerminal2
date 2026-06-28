using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using CortexTerminal.AgentRunner.Logging;

namespace CortexTerminal.AgentRunner.Commands;

/// <summary>
/// <c>cortap events [--session &lt;id&gt;] [--last N] [--event &lt;type&gt;] [--grep &lt;pattern&gt;] [--since &lt;duration&gt;] [--json]</c>
/// — query historical events from one session. Defaults to the most recent session.
/// </summary>
internal static class EventsCommand
{
    public static int Run(string[] args)
    {
        string? sessionId = null;
        int? last = null;
        string? eventType = null;
        string? grep = null;
        TimeSpan? since = null;
        var json = false;

        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--session": sessionId = Next(args, ref i); break;
                case "--last": last = int.TryParse(Next(args, ref i), out var n) ? n : null; break;
                case "--event": eventType = Next(args, ref i); break;
                case "--grep": grep = Next(args, ref i); break;
                case "--since": since = ParseDuration(Next(args, ref i)); break;
                case "--json": json = true; break;
                default:
                    if (sessionId is null && !args[i].StartsWith("--")) sessionId = args[i];
                    else
                    {
                        Console.Error.WriteLine($"cortap events: unknown arg '{args[i]}'");
                        return 2;
                    }
                    break;
            }
        }

        if (sessionId is null)
        {
            var latest = SessionStore.EnumerateSessions()
                .OrderByDescending(s => s.StartedAt ?? DateTimeOffset.MinValue)
                .FirstOrDefault();
            if (latest is null)
            {
                Console.Error.WriteLine("cortap events: no sessions found.");
                return 1;
            }
            sessionId = latest.SessionId;
            Console.Error.WriteLine($"cortap events: defaulting to most recent session '{sessionId}'.");
        }

        var eventsPath = SessionPaths.GetEventsPath(sessionId);
        if (!File.Exists(eventsPath))
        {
            Console.Error.WriteLine($"cortap events: session '{sessionId}' has no events.jsonl.");
            return 1;
        }

        Regex? grepRegex = null;
        if (grep is not null)
        {
            try { grepRegex = new Regex(grep, RegexOptions.Compiled); }
            catch (ArgumentException ex)
            {
                Console.Error.WriteLine($"cortap events: invalid --grep regex: {ex.Message}");
                return 2;
            }
        }

        var sinceCutoff = since is { } dur ? DateTimeOffset.UtcNow.Subtract(dur) : (DateTimeOffset?)null;

        var matched = new List<string>();
        try
        {
            using var fs = new FileStream(eventsPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var reader = new StreamReader(fs);
            string? line;
            while ((line = reader.ReadLine()) is not null)
            {
                if (FilterMatches(line, eventType, grepRegex, sinceCutoff))
                {
                    matched.Add(line);
                }
            }
        }
        catch (IOException ex)
        {
            Console.Error.WriteLine($"cortap events: failed to read {eventsPath}: {ex.Message}");
            return 1;
        }

        if (last is { } lim && matched.Count > lim)
        {
            matched = matched.Skip(matched.Count - lim).ToList();
        }

        foreach (var line in matched)
        {
            Console.Out.WriteLine(json ? EventFormatter.FormatRaw(line) : EventFormatter.Format(line));
        }

        Console.Error.WriteLine($"{matched.Count} event(s).");
        return 0;
    }

    private static string? Next(string[] args, ref int i)
    {
        if (i + 1 >= args.Length) return null;
        i++;
        return args[i];
    }

    private static TimeSpan? ParseDuration(string? s)
    {
        if (string.IsNullOrEmpty(s)) return null;
        // 1h / 30m / 2d
        if (s.Length < 2) return null;
        var unit = s[^1];
        if (!int.TryParse(s[..^1], out var n)) return null;
        return unit switch
        {
            's' => TimeSpan.FromSeconds(n),
            'm' => TimeSpan.FromMinutes(n),
            'h' => TimeSpan.FromHours(n),
            'd' => TimeSpan.FromDays(n),
            _ => null,
        };
    }

    private static bool FilterMatches(string line, string? eventType, Regex? grep, DateTimeOffset? sinceCutoff)
    {
        JsonObject? obj;
        try { obj = JsonNode.Parse(line) as JsonObject; }
        catch (JsonException) { return false; }
        if (obj is null) return false;

        if (eventType is not null)
        {
            var actual = obj["event_type"]?.GetValue<string>();
            if (!string.Equals(actual, eventType, StringComparison.OrdinalIgnoreCase)) return false;
        }

        if (sinceCutoff is { } cutoff)
        {
            var ts = obj["ts"]?.GetValue<string>();
            if (ts is not null && DateTimeOffset.TryParse(ts, out var d) && d < cutoff) return false;
        }

        if (grep is not null && !grep.IsMatch(line)) return false;

        return true;
    }
}
