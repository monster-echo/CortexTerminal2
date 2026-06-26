using CortexTerminal.Contracts.Sessions;

namespace CortexTerminal.Worker.Agent;

/// <summary>
/// Looks up the <see cref="IAgentAdapter"/> for a given <see cref="AgentKind"/>.
/// Phase 2 registers no adapters (Worker-side plumbing only); Phase 4+ adds
/// ClaudeCodeAdapter, CodexAdapter, OpenCodeAdapter.
/// </summary>
public interface IAgentAdapterRegistry
{
    IAgentAdapter? Resolve(AgentKind kind);
    IAgentAdapter? ResolveByName(string? name);
}
