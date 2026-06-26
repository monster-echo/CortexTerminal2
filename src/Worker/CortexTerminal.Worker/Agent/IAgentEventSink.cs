using CortexTerminal.Contracts.Streaming;

namespace CortexTerminal.Worker.Agent;

/// <summary>
/// Receives parsed agent activity frames from the loopback HTTP endpoint.
/// The Phase 2.2 implementation just logs; Phase 2.5 swaps in a sink that
/// forwards to the gateway via the worker SignalR connection.
/// </summary>
public interface IAgentEventSink
{
    Task DispatchAsync(BaseAgentActivityFrame frame, CancellationToken cancellationToken);
}
