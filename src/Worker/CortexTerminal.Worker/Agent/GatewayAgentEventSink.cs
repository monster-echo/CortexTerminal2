using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Registration;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Agent;

/// <summary>
/// Forwards parsed agent activity frames to the gateway via the worker SignalR connection.
/// One hub method per concrete frame type keeps MessagePack serialization polymorphism-free.
/// </summary>
public sealed class GatewayAgentEventSink : IAgentEventSink
{
    private readonly IWorkerGatewayClient _gateway;
    private readonly ILogger<GatewayAgentEventSink> _logger;

    public GatewayAgentEventSink(IWorkerGatewayClient gateway, ILogger<GatewayAgentEventSink> logger)
    {
        _gateway = gateway;
        _logger = logger;
    }

    public Task DispatchAsync(BaseAgentActivityFrame frame, CancellationToken cancellationToken)
    {
        try
        {
            return frame switch
            {
                AgentStartedFrame f => _gateway.ForwardAgentStartedAsync(f, cancellationToken),
                AgentPromptSubmittedFrame f => _gateway.ForwardAgentPromptSubmittedAsync(f, cancellationToken),
                AgentToolCallFrame f => _gateway.ForwardAgentToolCallAsync(f, cancellationToken),
                AgentStoppedFrame f => _gateway.ForwardAgentStoppedAsync(f, cancellationToken),
                AgentSessionEndedFrame f => _gateway.ForwardAgentSessionEndedAsync(f, cancellationToken),
                AgentSubagentStoppedFrame f => _gateway.ForwardAgentSubagentStoppedAsync(f, cancellationToken),
                AgentNotifiedFrame f => _gateway.ForwardAgentNotifiedAsync(f, cancellationToken),
                AgentCompactingFrame f => _gateway.ForwardAgentCompactingAsync(f, cancellationToken),
                AgentTitleUpdatedFrame f => _gateway.ForwardAgentTitleUpdatedAsync(f, cancellationToken),
                _ => throw new InvalidOperationException($"Unknown agent activity frame type: {frame.GetType().FullName}")
            };
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "Failed to forward agent activity frame {FrameType}.", frame.GetType().Name);
            throw;
        }
    }
}
