using CortexTerminal.Contracts.Sessions;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Agent;

/// <summary>
/// Default registry: discovers adapters via DI (IEnumerable&lt;IAgentAdapter&gt;).
/// Phase 2 has none registered — every hook event gets logged and dropped until
/// Phase 4 lands the first concrete adapter.
/// </summary>
public sealed class AgentAdapterRegistry : IAgentAdapterRegistry
{
    private readonly IReadOnlyDictionary<AgentKind, IAgentAdapter> _byKind;
    private readonly IReadOnlyDictionary<string, IAgentAdapter> _byName;
    private readonly ILogger<AgentAdapterRegistry> _logger;

    public AgentAdapterRegistry(IEnumerable<IAgentAdapter> adapters, ILogger<AgentAdapterRegistry> logger)
    {
        _logger = logger;
        var list = adapters?.ToArray() ?? Array.Empty<IAgentAdapter>();
        _byKind = list.ToDictionary(a => a.Kind);
        _byName = list.ToDictionary(a => AgentKindNames.ToName(a.Kind) ?? a.Kind.ToString(), StringComparer.OrdinalIgnoreCase);
    }

    public IAgentAdapter? Resolve(AgentKind kind)
    {
        if (_byKind.TryGetValue(kind, out var adapter)) return adapter;
        _logger.LogDebug("No adapter registered for AgentKind {Kind}.", kind);
        return null;
    }

    public IAgentAdapter? ResolveByName(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return null;
        if (_byName.TryGetValue(name, out var adapter)) return adapter;
        _logger.LogDebug("No adapter registered for agent kind name '{Name}'.", name);
        return null;
    }
}
