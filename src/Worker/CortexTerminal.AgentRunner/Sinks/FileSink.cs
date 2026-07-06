using System.Collections.Concurrent;
using System.Text;
using System.Text.Json.Nodes;
using CortexTerminal.AgentRunner.Logging;

namespace CortexTerminal.AgentRunner.Sinks;

/// <summary>
/// Append every event as one JSON object per line to
/// <c>~/.corterm/sessions/&lt;sessionId&gt;/events.jsonl</c>. Opens/closes the file on each
/// call so concurrent hook subprocesses can append without coordination.
///
/// <para>
/// .NET's <c>FileStream</c> with <c>FileMode.Append</c> does <b>not</b> use <c>O_APPEND</c> on
/// Unix — it seeks to end before each write, which races under in-process concurrency. So we
/// serialize writes for the same <c>events.jsonl</c> path with a per-path lock. Cross-process
/// concurrency (the real production pattern: separate cortap hook subprocesses) is
/// handled by the OS — each process holds its own lock instance, and the kernel's append-mode
/// atomicity handles inter-process writes for payloads under <c>PIPE_BUF</c> (≥512 bytes; our
/// payloads are ~200).
/// </para>
///
/// <para>
/// The envelope is augmented with a top-level <c>ts</c> (RFC 3339) field so readers see when
/// cortap received the event, even if the underlying payload has its own timestamps.
/// </para>
/// </summary>
internal sealed class FileSink : IAgentEventSink
{
    private static readonly ConcurrentDictionary<string, object> PathLocks = new();

    private readonly string _sessionId;
    private readonly string _home;

    public FileSink(string sessionId, string? home = null)
    {
        if (string.IsNullOrEmpty(sessionId)) throw new ArgumentException("sessionId must not be empty", nameof(sessionId));
        _sessionId = sessionId;
        _home = home ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

        // Pre-create the session directory so ForwardAsync doesn't fight to mkdir the same
        // path across hook subprocesses. Idempotent — safe to call again on each ForwardAsync.
        var eventsPath = SessionPaths.GetEventsPath(_sessionId, _home);
        var dir = System.IO.Path.GetDirectoryName(eventsPath);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
    }

    public Task<string> ForwardAsync(string envelopeJson, CancellationToken ct)
    {
        var eventsPath = SessionPaths.GetEventsPath(_sessionId, _home);
        var line = BuildTimestampedLine(envelopeJson);
        var bytes = Encoding.UTF8.GetBytes(line + "\n");

        var pathLock = PathLocks.GetOrAdd(eventsPath, _ => new object());
        lock (pathLock)
        {
            using var fs = new FileStream(
                eventsPath,
                FileMode.Append,
                FileAccess.Write,
                FileShare.ReadWrite | FileShare.Delete,
                bufferSize: bytes.Length,
                useAsync: false);
            fs.Write(bytes, 0, bytes.Length);
        }
        return Task.FromResult(string.Empty);
    }

    private static string BuildTimestampedLine(string envelopeJson)
    {
        var node = JsonNode.Parse(envelopeJson);
        if (node is JsonObject obj)
        {
            obj["ts"] = DateTimeOffset.UtcNow.ToString("O");
            return obj.ToJsonString();
        }
        return envelopeJson;
    }
}
