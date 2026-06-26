using System.Net.Http.Headers;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace CortexTerminal.AgentRunner;

/// <summary>
/// The wrapper's <c>hook</c> subcommand. Each agent's settings.json configures hooks that
/// exec <c>corterm-agent &lt;kind&gt; hook</c>; Claude Code / Codex feed the event payload
/// on stdin. This subcommand wraps the raw payload in the Corterm envelope (session_id,
/// agent_kind, event_type, payload) and POSTs to the loopback HTTP endpoint on the Worker.
///
/// The session_id is taken from <c>CORTERM_SESSION_ID</c> (the Corterm session, not the
/// agent's internal session id which lives inside the payload). event_type is read from the
/// payload's <c>hook_event_name</c> field (Claude Code convention).
/// </summary>
public static class HookForwarder
{
    private static readonly HttpClient HttpClient = new() { Timeout = TimeSpan.FromSeconds(10) };

    public static int Run(string[] args)
    {
        if (args.Length == 0)
        {
            Console.Error.WriteLine("usage: corterm-agent hook <kind>");
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
            Console.Error.WriteLine($"corterm-agent hook: unknown kind '{kind}'");
            return 2;
        }

        var hookUrl = Environment.GetEnvironmentVariable("CORTERM_AGENT_HOOK_URL");
        var sessionId = Environment.GetEnvironmentVariable("CORTERM_SESSION_ID");
        if (string.IsNullOrEmpty(hookUrl) || string.IsNullOrEmpty(sessionId))
        {
            Console.Error.WriteLine("corterm-agent hook: missing CORTERM_AGENT_HOOK_URL or CORTERM_SESSION_ID");
            return 1;
        }

        string body;
        try
        {
            body = Console.In.ReadToEnd();
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"corterm-agent hook: failed to read stdin: {ex.Message}");
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

        try
        {
            return PostEnvelope(hookUrl!, envelopeJson) ? 0 : 1;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"corterm-agent hook: failed to POST to {hookUrl}: {ex.Message}");
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

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static bool PostEnvelope(string hookUrl, string envelopeJson)
    {
        using var content = new StringContent(envelopeJson, Encoding.UTF8);
        content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        using var resp = HttpClient.PostAsync(hookUrl, content).GetAwaiter().GetResult();
        return resp.IsSuccessStatusCode || resp.StatusCode == System.Net.HttpStatusCode.Accepted;
    }
}
