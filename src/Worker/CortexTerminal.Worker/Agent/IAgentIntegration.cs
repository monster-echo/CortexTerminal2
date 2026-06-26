namespace CortexTerminal.Worker.Agent;

/// <summary>
/// Provides the per-Worker agent tracking configuration: the loopback HTTP
/// endpoint that hook events POST to, the directory where shim scripts live
/// (prepended to PTY PATH), and the original PATH so the wrapper binary can
/// locate the real agent binary.
/// </summary>
public interface IAgentIntegration
{
    /// <summary>True when agent tracking is wired up (HTTP endpoint running, shims installed).</summary>
    bool Enabled { get; }

    /// <summary>Loopback HTTP URL that hook events should POST to, e.g. http://127.0.0.1:51423/agent-event.</summary>
    string HookUrl { get; }

    /// <summary>Directory containing claude/codex/opencode shim scripts. Prepended to PTY PATH.</summary>
    string ShimsDir { get; }

    /// <summary>PATH before the shim dir was prepended. The wrapper uses this to find the real agent binary.</summary>
    string OriginalPath { get; }
}
