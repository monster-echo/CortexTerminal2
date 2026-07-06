namespace CortexTerminal.AgentRunner.Sinks;

/// <summary>
/// One event destination. HookForwarder builds the envelope JSON once and dispatches it to all
/// registered sinks in order. Implementations must be thread-safe — a single sink instance may
/// receive events from multiple hook invocations concurrently.
///
/// <para>
/// The return value is the response body the sink produced (e.g. HTTP response from the Worker).
/// Non-network sinks return <see cref="string.Empty"/>. <see cref="CompositeSink"/> returns the
/// first non-empty response so HookForwarder can forward it to stdout — Claude Code parses
/// <c>UserPromptSubmit</c> hook stdout as JSON with <c>hookSpecificOutput.additionalContext</c>
/// to inject context into the upcoming turn.
/// </para>
/// </summary>
internal interface IAgentEventSink
{
    Task<string> ForwardAsync(string envelopeJson, CancellationToken ct);
}
