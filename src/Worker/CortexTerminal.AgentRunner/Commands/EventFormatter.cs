using System.Text.Json;
using System.Text.Json.Nodes;

namespace CortexTerminal.AgentRunner.Commands;

/// <summary>
/// Renders one events.jsonl line as a human-friendly single-line summary. Keeps the same
/// format across <c>tail</c> and <c>events</c> so users see consistent output. Format:
/// <code>[12:34:56] EventType        summary</code>
/// </summary>
internal static class EventFormatter
{
    public static string Format(string jsonLine)
    {
        JsonObject? obj;
        try
        {
            obj = JsonNode.Parse(jsonLine) as JsonObject;
        }
        catch (JsonException)
        {
            return jsonLine;
        }
        if (obj is null) return jsonLine;

        var ts = obj["ts"]?.GetValue<string>();
        var eventType = obj["event_type"]?.GetValue<string>() ?? "?";
        var payload = obj["payload"] as JsonObject;

        var time = TryParseDate(ts);
        var summary = FormatSummary(eventType, payload);

        var timeStr = time?.LocalDateTime.ToString("HH:mm:ss") ?? "??:??:??";
        return $"[{timeStr}] {eventType,-18} {summary}";
    }

    public static string FormatRaw(string jsonLine)
    {
        // Pretty-printed JSON for `--json` mode (events command). Just returns the line as-is.
        return jsonLine;
    }

    private static string FormatSummary(string eventType, JsonObject? payload)
    {
        if (payload is null) return string.Empty;

        return eventType switch
        {
            "SessionStart" => $"cwd={payload["cwd"]?.GetValue<string>() ?? "?"}",
            "UserPromptSubmit" => Quote(payload["prompt"]?.GetValue<string>()),
            "PreToolUse" => $"{payload["tool_name"]?.GetValue<string>() ?? "?"}  {Quote(Truncate(ExtractToolCommand(payload), 60))}",
            "PostToolUse" => $"{payload["tool_name"]?.GetValue<string>() ?? "?"}  {Quote(Truncate(ExtractToolCommand(payload), 60))}  {FormatToolResult(payload)}",
            "Stop" => FormatStop(payload),
            "SessionEnd" => string.Empty,
            "Notification" => Quote(payload["message"]?.GetValue<string>()),
            "SubagentStop" => string.Empty,
            "PreCompact" => string.Empty,
            _ => string.Empty,
        };
    }

    private static string? ExtractToolCommand(JsonObject payload)
    {
        if (payload["tool_input"] is JsonObject input)
        {
            return input["command"]?.GetValue<string>()
                ?? input["file_path"]?.GetValue<string>()
                ?? input["pattern"]?.GetValue<string>();
        }
        return null;
    }

    private static string FormatToolResult(JsonObject payload)
    {
        if (payload["tool_response"] is JsonObject resp)
        {
            var isError = resp["is_error"]?.GetValue<bool>() ?? false;
            return isError ? "ERROR" : "ok";
        }
        return string.Empty;
    }

    private static string FormatStop(JsonObject payload)
    {
        if (payload["stop_hook_active"]?.GetValue<bool>() ?? false) return "stop_hook_active";
        return string.Empty;
    }

    private static string Quote(string? s)
    {
        if (string.IsNullOrEmpty(s)) return "\"\"";
        s = s.Replace("\n", " ").Replace("\r", string.Empty);
        if (s.Length > 60) s = s[..57] + "...";
        return $"\"{s}\"";
    }

    private static string Truncate(string? s, int max)
    {
        if (string.IsNullOrEmpty(s)) return string.Empty;
        return s.Length <= max ? s : s[..(max - 3)] + "...";
    }

    private static DateTimeOffset? TryParseDate(string? s)
    {
        if (string.IsNullOrEmpty(s)) return null;
        return DateTimeOffset.TryParse(s, out var d) ? d : null;
    }
}
