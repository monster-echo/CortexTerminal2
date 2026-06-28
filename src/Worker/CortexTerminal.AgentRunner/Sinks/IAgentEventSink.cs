namespace CortexTerminal.AgentRunner.Sinks;

/// <summary>
/// One event destination. HookForwarder builds the envelope JSON once and dispatches it to all
/// registered sinks in order. Implementations must be thread-safe — a single sink instance may
/// receive events from multiple hook invocations concurrently.
/// </summary>
internal interface IAgentEventSink
{
    Task ForwardAsync(string envelopeJson, CancellationToken ct);
}
