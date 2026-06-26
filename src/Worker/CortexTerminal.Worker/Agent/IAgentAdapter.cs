using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using System.Text.Json.Nodes;

namespace CortexTerminal.Worker.Agent;

/// <summary>
/// Pluggable adapter for an AI coding agent (Claude Code / Codex / OpenCode).
/// Implementations know how to spawn the real agent binary, generate hook
/// configuration, and parse hook events into structured activity frames.
/// </summary>
public interface IAgentAdapter
{
    AgentKind Kind { get; }

    /// <summary>Resolve the real agent binary path (skipping the Corterm shim dir).</summary>
    string? ResolveBinary();

    /// <summary>Environment variables to set on the spawned agent process (e.g. CLAUDE_SETTINGS_FILE).</summary>
    IReadOnlyDictionary<string, string> BuildEnvironment(AgentSessionContext context);

    /// <summary>Generate the temporary hook configuration file content.</summary>
    string GenerateHookConfig(AgentSessionContext context);

    /// <summary>Hook config filename expected by the agent (e.g. "settings.json" for Claude Code).</summary>
    string HookConfigFilename { get; }

    /// <summary>Parse a hook event payload into a structured activity frame, or null if uninteresting.</summary>
    BaseAgentActivityFrame? ParseEvent(string eventType, JsonObject payload, AgentSessionContext context);
}

