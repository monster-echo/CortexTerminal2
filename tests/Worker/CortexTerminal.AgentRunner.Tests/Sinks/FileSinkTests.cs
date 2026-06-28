using System.Text.Json.Nodes;
using CortexTerminal.AgentRunner.Logging;
using CortexTerminal.AgentRunner.Sinks;
using FluentAssertions;

namespace CortexTerminal.AgentRunner.Tests.Sinks;

/// <summary>
/// Validates FileSink: appends one JSON line per event, augments with a top-level "ts" field,
/// and lets multiple hook subprocesses append without coordination (atomic append, file share).
/// </summary>
public sealed class FileSinkTests
{
    [Fact]
    public async Task ForwardAsync_AppendsOneLinePerEvent()
    {
        using var dir = new TempHome();
        var sink = new FileSink("test-sess", dir.Path);
        var envelope = """{"session_id":"test-sess","agent_kind":"claude-code","event_type":"SessionStart","payload":{"cwd":"/tmp"}}""";

        await sink.ForwardAsync(envelope, CancellationToken.None);
        await sink.ForwardAsync(envelope, CancellationToken.None);

        var eventsPath = SessionPaths.GetEventsPath("test-sess", dir.Path);
        File.Exists(eventsPath).Should().BeTrue();
        var lines = await File.ReadAllLinesAsync(eventsPath);
        lines.Length.Should().Be(2);
    }

    [Fact]
    public async Task ForwardAsync_AddsTopLevelTimestamp()
    {
        using var dir = new TempHome();
        var sink = new FileSink("test-sess", dir.Path);
        var envelope = """{"session_id":"test-sess","agent_kind":"claude-code","event_type":"UserPromptSubmit","payload":{"prompt":"hi"}}""";

        await sink.ForwardAsync(envelope, CancellationToken.None);

        var eventsPath = SessionPaths.GetEventsPath("test-sess", dir.Path);
        var line = (await File.ReadAllLinesAsync(eventsPath))[0];
        var obj = JsonNode.Parse(line)!.AsObject();
        obj.ContainsKey("ts").Should().BeTrue();
        obj["event_type"]!.GetValue<string>().Should().Be("UserPromptSubmit");
        obj["payload"]!["prompt"]!.GetValue<string>().Should().Be("hi");
    }

    [Fact]
    public async Task ForwardAsync_AllowsConcurrentAppendsFromMultipleInstances()
    {
        using var dir = new TempHome();
        var envelope = """{"event_type":"Stop","payload":{}}""";

        var tasks = Enumerable.Range(0, 20).Select(i =>
        {
            var sink = new FileSink("concurrent-sess", dir.Path);
            return Task.Run(() => sink.ForwardAsync(envelope, CancellationToken.None));
        }).ToArray();

        await Task.WhenAll(tasks);

        var eventsPath = SessionPaths.GetEventsPath("concurrent-sess", dir.Path);
        var lines = await File.ReadAllLinesAsync(eventsPath);
        lines.Length.Should().Be(20);
    }

    private sealed class TempHome : IDisposable
    {
        public string Path { get; }
        public TempHome() => Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "corterm-home-" + Guid.NewGuid().ToString("N"));
        public void Dispose()
        {
            try { if (Directory.Exists(Path)) Directory.Delete(Path, recursive: true); } catch { }
        }
    }
}
