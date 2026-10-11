namespace CortexTerminal.Worker.Agent;

/// <summary>
/// Provides the per-Worker agent tracking configuration: whether tracking is enabled
/// and the loopback HTTP endpoint that Claude Code hook events POST to.
/// </summary>
public interface IAgentIntegration
{
    /// <summary>True when agent tracking is wired up (HTTP endpoint running, Claude Code hooks installed).</summary>
    bool Enabled { get; }

    /// <summary>Loopback HTTP URL that hook events should POST to, e.g. http://127.0.0.1:51423/agent-event.</summary>
    string HookUrl { get; }
}
