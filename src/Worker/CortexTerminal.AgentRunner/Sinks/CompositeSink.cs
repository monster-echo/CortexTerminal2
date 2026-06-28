namespace CortexTerminal.AgentRunner.Sinks;

/// <summary>
/// Fan-out sink: runs every inner sink in order, swallows per-sink failures so a broken sink
/// never blocks the others. The first failure is logged to stderr; subsequent failures are
/// logged the same way. This is intentional — losing one sink (e.g. Worker POST) should not
/// silently drop the FileSink (local JSONL log).
/// </summary>
internal sealed class CompositeSink : IAgentEventSink
{
    private readonly IReadOnlyList<IAgentEventSink> _sinks;

    public CompositeSink(IEnumerable<IAgentEventSink> sinks)
    {
        _sinks = sinks.ToArray();
    }

    public async Task ForwardAsync(string envelopeJson, CancellationToken ct)
    {
        foreach (var sink in _sinks)
        {
            try
            {
                await sink.ForwardAsync(envelopeJson, ct);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"cortap: {sink.GetType().Name} failed: {ex.Message}");
            }
        }
    }
}
