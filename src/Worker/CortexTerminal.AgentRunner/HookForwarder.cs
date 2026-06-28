using System.Text.Json;
using System.Text.Json.Nodes;
using CortexTerminal.AgentRunner.Sinks;

namespace CortexTerminal.AgentRunner;

/// <summary>
/// The wrapper's <c>hook</c> subcommand. Each agent's settings.json configures hooks that
/// exec <c>cortap hook &lt;kind&gt;</c>; Claude Code / Codex feed the event payload
/// on stdin. This subcommand wraps the raw payload in the Corterm envelope (session_id,
/// agent_kind, event_type, payload) and dispatches it through a sink chain:
///
/// <list type="bullet">
/// <item><c>FileSink</c> always writes the event to <c>events.jsonl</c> for offline analysis.</item>
/// <item><c>HttpSink</c> POSTs to the Worker loopback endpoint when <c>CORTERM_AGENT_HOOK_URL</c> is set.</item>
/// </list>
///
/// The session_id is taken from <c>CORTERM_SESSION_ID</c> (the Corterm session, not the
/// agent's internal session id which lives inside the payload). event_type is read from the
/// payload's <c>hook_event_name</c> field (Claude Code convention).
/// </summary>
public static class HookForwarder
{
    public static int Run(string[] args)
    {
        if (args.Length == 0)
        {
            Console.Error.WriteLine("usage: cortap hook <kind>");
            return 2;
        }

        var kind = args[0];
        var kindName = kind switch
        {
            "claude" => "claude-code",
            "codex" => "codex",
            "opencode" => "opencode",
            _ => null,
        };
        if (kindName is null)
        {
            Console.Error.WriteLine($"cortap hook: unknown kind '{kind}'");
            return 2;
        }

        var sessionId = Environment.GetEnvironmentVariable("CORTERM_SESSION_ID");
        if (string.IsNullOrEmpty(sessionId))
        {
            Console.Error.WriteLine("cortap hook: missing CORTERM_SESSION_ID");
            Console.Error.WriteLine("  Hooks must be invoked from a Corterm session (Worker or independent mode).");
            return 1;
        }

        string body;
        try
        {
            body = Console.In.ReadToEnd();
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"cortap hook: failed to read stdin: {ex.Message}");
            return 1;
        }

        if (string.IsNullOrWhiteSpace(body)) return 0;

        string envelopeJson;
        try
        {
            envelopeJson = BuildEnvelopeJson(body, sessionId!, kindName);
        }
        catch (JsonException)
        {
            return 0;
        }

        if (envelopeJson.Length == 0) return 0;

        var hookUrl = Environment.GetEnvironmentVariable("CORTERM_AGENT_HOOK_URL");
        var sinks = new List<IAgentEventSink> { new FileSink(sessionId!) };
        if (!string.IsNullOrEmpty(hookUrl))
        {
            sinks.Add(new HttpSink(hookUrl!));
        }

        var composite = new CompositeSink(sinks);
        try
        {
            composite.ForwardAsync(envelopeJson, CancellationToken.None).GetAwaiter().GetResult();
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"cortap hook: dispatch failed: {ex.Message}");
            return 1;
        }
    }

    internal static string BuildEnvelopeJson(string rawBody, string sessionId, string kindName)
    {
        var parseOptions = new JsonDocumentOptions
        {
            CommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true,
        };

        using var doc = JsonDocument.Parse(rawBody, parseOptions);
        var root = doc.RootElement;
        if (root.ValueKind != JsonValueKind.Object) return string.Empty;

        if (!root.TryGetProperty("hook_event_name", out var eventNameEl)) return string.Empty;
        var eventType = eventNameEl.GetString();
        if (string.IsNullOrEmpty(eventType)) return string.Empty;

        // Parse the raw body again into a JsonNode tree so we can nest it under "payload"
        // without triggering the reflection-based JsonSerializer (which isn't AOT-safe).
        var payloadNode = JsonNode.Parse(rawBody, documentOptions: parseOptions);
        if (payloadNode is null) return string.Empty;

        var envelope = new JsonObject
        {
            ["session_id"] = sessionId,
            ["agent_kind"] = kindName,
            ["event_type"] = eventType,
            ["payload"] = payloadNode,
        };
        return envelope.ToJsonString();
    }
}
