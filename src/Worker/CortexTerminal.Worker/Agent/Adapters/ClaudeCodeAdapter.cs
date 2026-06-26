using System.Text.Json;
using System.Text.Json.Nodes;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;

namespace CortexTerminal.Worker.Agent.Adapters;

/// <summary>
/// Parses Claude Code hook events (SessionStart / SessionEnd / UserPromptSubmit / PreToolUse /
/// PostToolUse / Stop / SubagentStop / Notification / PreCompact) into structured activity frames.
/// Each event payload is the JSON Claude Code passes to the hook command on stdin; the wrapper's
/// <c>hook</c> subcommand wraps it in the standard envelope and POSTs to the loopback HTTP
/// endpoint, which hands the payload here.
///
/// Reference: https://code.claude.com/docs/en/hooks
/// </summary>
public sealed class ClaudeCodeAdapter : IAgentAdapter
{
    public AgentKind Kind => AgentKind.ClaudeCode;

    public string HookConfigFilename => "settings.json";

    public string? ResolveBinary()
    {
        var explicitPath = Environment.GetEnvironmentVariable("CLAUDE_BINARY_PATH");
        if (!string.IsNullOrWhiteSpace(explicitPath) && File.Exists(explicitPath)) return explicitPath;

        var originalPath = Environment.GetEnvironmentVariable("CORTERM_ORIGINAL_PATH") ?? Environment.GetEnvironmentVariable("PATH");
        return AgentBinaryProbe.FindOnPath("claude", originalPath);
    }

    public IReadOnlyDictionary<string, string> BuildEnvironment(AgentSessionContext context)
        => new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["CLAUDE_CONFIG_DIR"] = context.TempConfigDir,
        };

    /// <summary>
    /// Generate the settings.json that wires each Claude Code hook event to the wrapper's
    /// <c>hook</c> subcommand. The wrapper reads the event payload from stdin, wraps it in the
    /// Corterm envelope, and POSTs to the loopback HTTP endpoint on the Worker.
    /// </summary>
    public string GenerateHookConfig(AgentSessionContext context)
    {
        var wrapperPath = Environment.ProcessPath
            ?? throw new InvalidOperationException("Cannot determine wrapper process path.");
        var command = $"\"{wrapperPath}\" hook claude-code";

        var hookEvents = new[]
        {
            "SessionStart",
            "SessionEnd",
            "UserPromptSubmit",
            "PreToolUse",
            "PostToolUse",
            "Stop",
            "SubagentStop",
            "Notification",
            "PreCompact",
        };

        var hooks = new JsonObject();
        foreach (var evt in hookEvents)
        {
            var entry = new JsonArray(new JsonObject
            {
                ["matcher"] = "*",
                ["hooks"] = new JsonArray(new JsonObject
                {
                    ["type"] = "command",
                    ["command"] = command,
                }),
            });
            hooks[evt] = entry;
        }

        var root = new JsonObject
        {
            ["hooks"] = hooks,
        };
        return root.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
    }

    /// <summary>
    /// Parse a single hook event payload into a structured frame, or null if the event isn't
    /// one Corterm tracks (e.g. PreToolUse — we only emit a frame on PostToolUse completion).
    /// </summary>
    public BaseAgentActivityFrame? ParseEvent(string eventType, JsonObject payload, AgentSessionContext context)
    {
        return eventType switch
        {
            "SessionStart" => ParseSessionStart(payload, context),
            "SessionEnd" => ParseSessionEnd(payload, context),
            "UserPromptSubmit" => ParseUserPromptSubmit(payload, context),
            "PostToolUse" => ParsePostToolUse(payload, context),
            "Stop" => ParseStop(payload, context),
            "SubagentStop" => ParseSubagentStop(payload, context),
            "Notification" => ParseNotification(payload, context),
            "PreCompact" => ParsePreCompact(payload, context),
            _ => null,
        };
    }

    private static AgentStartedFrame ParseSessionStart(JsonObject payload, AgentSessionContext context)
    {
        var agentSessionId = payload.TryGetPropertyValue("session_id", out var sid) ? sid?.GetValue<string>() : null;
        var workDir = payload.TryGetPropertyValue("cwd", out var cwd) ? cwd?.GetValue<string>() : null;
        return new AgentStartedFrame(context.SessionId, AgentKind.ClaudeCode, agentSessionId, workDir);
    }

    private static AgentPromptSubmittedFrame ParseUserPromptSubmit(JsonObject payload, AgentSessionContext context)
    {
        var prompt = payload.TryGetPropertyValue("prompt", out var p) ? p?.GetValue<string>() : null;
        return new AgentPromptSubmittedFrame(context.SessionId, prompt ?? string.Empty, PromptId: null);
    }

    private static AgentToolCallFrame ParsePostToolUse(JsonObject payload, AgentSessionContext context)
    {
        var toolName = payload.TryGetPropertyValue("tool_name", out var t) ? t?.GetValue<string>() : null;
        var inputJson = payload.TryGetPropertyValue("tool_input", out var ti) && ti is not null
            ? ti.ToJsonString()
            : null;
        var outputJson = payload.TryGetPropertyValue("tool_response", out var tr) && tr is not null
            ? tr.ToJsonString()
            : null;
        var isError = false;
        if (tr is JsonObject respObj
            && respObj.TryGetPropertyValue("is_error", out var ie)
            && ie is not null)
        {
            try { isError = ie.GetValue<bool>(); } catch (FormatException) { }
        }

        return new AgentToolCallFrame(
            context.SessionId,
            toolName ?? "unknown",
            inputJson,
            outputJson,
            DurationMs: 0,
            IsError: isError);
    }

    private static AgentStoppedFrame ParseStop(JsonObject payload, AgentSessionContext context)
    {
        // Stop hook doesn't carry cost/token totals — those live in the transcript JSONL.
        // The transcript watcher (Phase 4.1) will backfill them; for now we emit a bare stop frame.
        return new AgentStoppedFrame(context.SessionId, TotalCostUsd: null, TotalTokensIn: null, TotalTokensOut: null, StopReason: null);
    }

    private static AgentSessionEndedFrame ParseSessionEnd(JsonObject payload, AgentSessionContext context)
    {
        var reason = payload.TryGetPropertyValue("reason", out var r) ? r?.GetValue<string>() : null;
        return new AgentSessionEndedFrame(context.SessionId, reason);
    }

    private static AgentSubagentStoppedFrame ParseSubagentStop(JsonObject payload, AgentSessionContext context)
    {
        var subagentId = payload.TryGetPropertyValue("subagent_id", out var sid) ? sid?.GetValue<string>() : null;
        return new AgentSubagentStoppedFrame(context.SessionId, subagentId);
    }

    private static AgentNotifiedFrame ParseNotification(JsonObject payload, AgentSessionContext context)
    {
        var title = payload.TryGetPropertyValue("title", out var t) ? t?.GetValue<string>() : null;
        var body = payload.TryGetPropertyValue("message", out var m) ? m?.GetValue<string>() : null;
        return new AgentNotifiedFrame(context.SessionId, title, body);
    }

    private static AgentCompactingFrame ParsePreCompact(JsonObject payload, AgentSessionContext context)
    {
        var trigger = payload.TryGetPropertyValue("trigger", out var tr) ? tr?.GetValue<string>() : null;
        return new AgentCompactingFrame(context.SessionId, trigger);
    }
}
