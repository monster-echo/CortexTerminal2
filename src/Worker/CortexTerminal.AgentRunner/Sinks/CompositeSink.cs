namespace CortexTerminal.AgentRunner.Sinks;

/// <summary>
/// Fan-out sink: runs every inner sink in order, swallows per-sink failures so a broken sink
/// never blocks the others. The first failure is logged to stderr; subsequent failures are
/// logged the same way. This is intentional — losing one sink (e.g. Worker POST) should not
/// silently drop the FileSink (local JSONL log).
///
/// <para>
/// Returns the first non-empty response body from any inner sink. HookForwarder writes this to
/// stdout so Claude Code can pick it up as <c>additionalContext</c> for the upcoming turn.
/// </para>
/// </summary>
internal sealed class CompositeSink : IAgentEventSink
{
    private readonly IReadOnlyList<IAgentEventSink> _sinks;

    public CompositeSink(IEnumerable<IAgentEventSink> sinks)
    {
        _sinks = sinks.ToArray();
    }

    public async Task<string> ForwardAsync(string envelopeJson, CancellationToken ct)
    {
        var response = string.Empty;
        foreach (var sink in _sinks)
        {
            try
            {
                var sinkResponse = await sink.ForwardAsync(envelopeJson, ct);
                if (string.IsNullOrEmpty(response) && !string.IsNullOrEmpty(sinkResponse))
                {
                    response = sinkResponse;
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"cortap: {sink.GetType().Name} failed: {ex.Message}");
            }
        }
        return response;
    }
}
