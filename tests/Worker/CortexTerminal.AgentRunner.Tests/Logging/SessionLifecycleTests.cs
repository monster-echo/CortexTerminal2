using System.Text.Json.Nodes;
using CortexTerminal.AgentRunner.Logging;
using FluentAssertions;

namespace CortexTerminal.AgentRunner.Tests.Logging;

/// <summary>
/// Validates SessionLifecycle writes meta.json + pid on Start, marks endedAt on Stop, deletes
/// pid on Stop, and ReapOrphanedSessions marks stale sessions as crashed.
/// </summary>
public sealed class SessionLifecycleTests
{
    [Fact]
    public void Start_WritesMetaJsonWithSessionIdKindCwd()
    {
        using var dir = new TempHome();
        using (var lifecycle = new SessionLifecycle("sess-start", "claude-code", "/tmp/work", dir.Path))
        {
            lifecycle.Start();

            var meta = ReadMeta(dir.Path, "sess-start");
            meta["sessionId"]!.GetValue<string>().Should().Be("sess-start");
            meta["kind"]!.GetValue<string>().Should().Be("claude-code");
            meta["cwd"]!.GetValue<string>().Should().Be("/tmp/work");
            meta["startedAt"]!.GetValue<string>().Should().NotBeNullOrEmpty();
            meta["pid"]!.GetValue<int>().Should().Be(Environment.ProcessId);
            meta.ContainsKey("endedAt").Should().BeFalse();
        }

        // Stop on dispose: endedAt now set, pid file removed.
        var metaAfter = ReadMeta(dir.Path, "sess-start");
        metaAfter.ContainsKey("endedAt").Should().BeTrue();
        File.Exists(SessionPaths.GetPidPath("sess-start", dir.Path)).Should().BeFalse();
    }

    [Fact]
    public void StartThenStop_PreserveMetaCore()
    {
        using var dir = new TempHome();
        var lifecycle = new SessionLifecycle("sess-preserve", "claude-code", "/work", dir.Path);
        lifecycle.Start();
        lifecycle.Stop();

        var meta = ReadMeta(dir.Path, "sess-preserve");
        meta["sessionId"]!.GetValue<string>().Should().Be("sess-preserve");
        meta["kind"]!.GetValue<string>().Should().Be("claude-code");
        meta["cwd"]!.GetValue<string>().Should().Be("/work");
        meta.ContainsKey("startedAt").Should().BeTrue();
        meta.ContainsKey("endedAt").Should().BeTrue();
    }

    [Fact]
    public void ReapOrphanedSessions_MarksStaleSessionsAsCrashed()
    {
        using var dir = new TempHome();
        // Session with pid pointing at a dead PID and no endedAt — looks orphaned.
        var sessionDir = SessionPaths.GetSessionDir("orphan", dir.Path);
        Directory.CreateDirectory(sessionDir);
        var meta = new JsonObject
        {
            ["sessionId"] = "orphan",
            ["kind"] = "claude-code",
            ["cwd"] = "/tmp",
            ["startedAt"] = DateTimeOffset.UtcNow.ToString("O"),
            ["pid"] = 999_999, // almost certainly dead
        };
        File.WriteAllText(SessionPaths.GetMetaPath("orphan", dir.Path), meta.ToJsonString());
        File.WriteAllText(SessionPaths.GetPidPath("orphan", dir.Path), "999999");

        var reaped = SessionLifecycle.ReapOrphanedSessions(dir.Path);

        reaped.Should().BeGreaterThanOrEqualTo(1);
        var metaAfter = ReadMeta(dir.Path, "orphan");
        metaAfter.ContainsKey("endedAt").Should().BeTrue();
        metaAfter["crashed"]!.GetValue<bool>().Should().BeTrue();
        File.Exists(SessionPaths.GetPidPath("orphan", dir.Path)).Should().BeFalse();
    }

    [Fact]
    public void ReapOrphanedSessions_NoOpWhenNoSessions()
    {
        using var dir = new TempHome();
        var reaped = SessionLifecycle.ReapOrphanedSessions(dir.Path);
        reaped.Should().Be(0);
    }

    private static JsonObject ReadMeta(string home, string sessionId)
    {
        var content = File.ReadAllText(SessionPaths.GetMetaPath(sessionId, home));
        return JsonNode.Parse(content)!.AsObject();
    }

    private sealed class TempHome : IDisposable
    {
        public string Path { get; }
        public TempHome() => Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "corterm-lifecycle-" + Guid.NewGuid().ToString("N"));
        public void Dispose()
        {
            try { if (Directory.Exists(Path)) Directory.Delete(Path, recursive: true); } catch { }
        }
    }
}
