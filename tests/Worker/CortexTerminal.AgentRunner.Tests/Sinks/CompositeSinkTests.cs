using CortexTerminal.AgentRunner.Sinks;
using FluentAssertions;

namespace CortexTerminal.AgentRunner.Tests.Sinks;

/// <summary>
/// Verifies CompositeSink runs every sink in order and isolates failures — one sink throwing
/// must not block the others. This is the contract that lets us compose FileSink + HttpSink
/// safely: a POST failure must not drop the local log line.
/// </summary>
public sealed class CompositeSinkTests
{
    [Fact]
    public async Task ForwardAsync_DispatchesToAllSinksInOrder()
    {
        var calls = new List<string>();
        var a = new CallbackSink(_ => { calls.Add("a"); return Task.CompletedTask; });
        var b = new CallbackSink(_ => { calls.Add("b"); return Task.CompletedTask; });
        var c = new CallbackSink(_ => { calls.Add("c"); return Task.CompletedTask; });

        var composite = new CompositeSink(new[] { a, b, c });
        await composite.ForwardAsync("{}", CancellationToken.None);

        calls.Should().BeEquivalentTo(new[] { "a", "b", "c" }, opts => opts.WithStrictOrdering());
    }

    [Fact]
    public async Task ForwardAsync_ContinuesWhenOneSinkThrows()
    {
        var calls = new List<string>();
        var a = new CallbackSink(_ => { calls.Add("a"); return Task.CompletedTask; });
        var b = new CallbackSink(_ => throw new InvalidOperationException("boom"));
        var c = new CallbackSink(_ => { calls.Add("c"); return Task.CompletedTask; });

        var composite = new CompositeSink(new[] { a, b, c });
        await composite.ForwardAsync("{}", CancellationToken.None);

        // a and c both ran despite b throwing.
        calls.Should().BeEquivalentTo(new[] { "a", "c" });
    }

    [Fact]
    public async Task ForwardAsync_EmptySinkList_ReturnsSuccessfully()
    {
        var composite = new CompositeSink(Array.Empty<IAgentEventSink>());
        var act = async () => await composite.ForwardAsync("{}", CancellationToken.None);
        await act.Should().NotThrowAsync();
    }

    private sealed class CallbackSink : IAgentEventSink
    {
        private readonly Func<string, Task> _onForward;
        public CallbackSink(Func<string, Task> onForward) => _onForward = onForward;
        public Task ForwardAsync(string envelopeJson, CancellationToken ct) => _onForward(envelopeJson);
    }
}
