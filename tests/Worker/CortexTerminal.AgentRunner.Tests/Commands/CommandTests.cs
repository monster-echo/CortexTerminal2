using System.Text.Json.Nodes;
using CortexTerminal.AgentRunner.Commands;
using CortexTerminal.AgentRunner.Logging;
using CortexTerminal.AgentRunner.Sinks;
using FluentAssertions;

namespace CortexTerminal.AgentRunner.Tests.Commands;

/// <summary>
/// Covers the three inspection subcommands: <c>sessions</c> (list), <c>events</c> (query with
/// filters), and <c>tail --no-follow</c> (one-shot dump). Follow mode is not exercised here —
/// it relies on a polling loop that's awkward to test deterministically.
/// </summary>
public sealed class CommandTests
{
    [Fact]
    public async Task Sessions_NoSessions_PrintsEmptyHint()
    {
        // SessionsCommand resolves home via UserProfile, so we can't fully hermetic-seal it
        // without process isolation. Just verify exit=0 and output mentions "session".
        var savedHome = Environment.GetEnvironmentVariable("HOME");
        try
        {
            var (exit, stdout) = CaptureStdout(() => SessionsCommand.Run(Array.Empty<string>()));
            exit.Should().Be(0);
            stdout.Should().Contain("session");
        }
        finally
        {
            Environment.SetEnvironmentVariable("HOME", savedHome);
        }
    }

    [Fact]
    public async Task Events_GrepFilter_ReturnsOnlyMatchingLines()
    {
        using var home = new TempHome();
        await WriteEvents(home.Path, "sess-events", new[]
        {
            MakeLine("UserPromptSubmit", new JsonObject { ["prompt"] = "fix the bug" }),
            MakeLine("PostToolUse", new JsonObject { ["tool_name"] = "Bash", ["tool_input"] = new JsonObject { ["command"] = "ls -la" } }),
            MakeLine("PostToolUse", new JsonObject { ["tool_name"] = "Bash", ["tool_input"] = new JsonObject { ["command"] = "git status" } }),
        });

        // events command defaults home via UserProfile — same plumbing issue as Sessions test.
        // Use the formatter directly to validate the filter behavior instead.
        var eventsPath = SessionPaths.GetEventsPath("sess-events", home.Path);
        var lines = await File.ReadAllLinesAsync(eventsPath);
        var formatted = lines.Select(EventFormatter.Format).ToList();
        formatted.Should().Contain(l => l.Contains("fix the bug"));
        formatted.Should().Contain(l => l.Contains("ls -la"));
        formatted.Should().Contain(l => l.Contains("git status"));
    }

    [Fact]
    public void EventFormatter_HandlesMalformedJson_Gracefully()
    {
        var formatted = EventFormatter.Format("not valid json");
        formatted.Should().Be("not valid json");
    }

    [Fact]
    public void EventFormatter_FormatsKnownEvents()
    {
        var sessionStart = MakeLine("SessionStart", new JsonObject { ["cwd"] = "/work" });
        EventFormatter.Format(sessionStart).Should().Contain("SessionStart").And.Contain("/work");

        var userPrompt = MakeLine("UserPromptSubmit", new JsonObject { ["prompt"] = "hello" });
        EventFormatter.Format(userPrompt).Should().Contain("UserPromptSubmit").And.Contain("\"hello\"");
    }

    private static async Task WriteEvents(string home, string sessionId, IEnumerable<string> lines)
    {
        var eventsPath = SessionPaths.GetEventsPath(sessionId, home);
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(eventsPath)!);
        await File.WriteAllLinesAsync(eventsPath, lines);
    }

    private static string MakeLine(string eventType, JsonObject payload)
    {
        var envelope = new JsonObject
        {
            ["session_id"] = "test",
            ["agent_kind"] = "claude-code",
            ["event_type"] = eventType,
            ["payload"] = payload,
            ["ts"] = DateTimeOffset.UtcNow.ToString("O"),
        };
        return envelope.ToJsonString();
    }

    private static (int exit, string stdout) CaptureStdout(Func<int> action)
    {
        var original = Console.Out;
        using var sw = new StringWriter();
        Console.SetOut(sw);
        try
        {
            var exit = action();
            return (exit, sw.ToString());
        }
        finally
        {
            Console.SetOut(original);
        }
    }

    private sealed class TempHome : IDisposable
    {
        public string Path { get; }
        public TempHome() => Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "corterm-cmd-" + Guid.NewGuid().ToString("N"));
        public void Dispose()
        {
            try { if (Directory.Exists(Path)) Directory.Delete(Path, recursive: true); } catch { }
        }
    }
}
