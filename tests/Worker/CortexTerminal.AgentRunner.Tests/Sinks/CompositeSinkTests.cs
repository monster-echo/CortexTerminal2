using CortexTerminal.AgentRunner.Sinks;
using FluentAssertions;

namespace CortexTerminal.AgentRunner.Tests.Sinks;

/// <summary>
/// Verifies CompositeSink runs every sink in order and isolates failures — one sink throwing
/// must not block the others. This is the contract that lets us compose FileSink + HttpSink
/// safely: a POST failure must not drop the local log line.
///
/// Also verifies response-body propagation: CompositeSink returns the first non-empty response
/// so HookForwarder can forward the Worker's hook response (additionalContext for Claude Code)
/// to stdout.
/// </summary>
public sealed class CompositeSinkTests
{
    [Fact]
    public async Task ForwardAsync_DispatchesToAllSinksInOrder()
    {
        var calls = new List<string>();
        var a = new CallbackSink(_ => { calls.Add("a"); return Task.FromResult(string.Empty); });
        var b = new CallbackSink(_ => { calls.Add("b"); return Task.FromResult(string.Empty); });
        var c = new CallbackSink(_ => { calls.Add("c"); return Task.FromResult(string.Empty); });

        var composite = new CompositeSink(new[] { a, b, c });
        await composite.ForwardAsync("{}", CancellationToken.None);

        calls.Should().BeEquivalentTo(new[] { "a", "b", "c" }, opts => opts.WithStrictOrdering());
    }

    [Fact]
    public async Task ForwardAsync_ContinuesWhenOneSinkThrows()
    {
        var calls = new List<string>();
        var a = new CallbackSink(_ => { calls.Add("a"); return Task.FromResult(string.Empty); });
        var b = new CallbackSink(_ => throw new InvalidOperationException("boom"));
        var c = new CallbackSink(_ => { calls.Add("c"); return Task.FromResult(string.Empty); });

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

    [Fact]
    public async Task ForwardAsync_ReturnsFirstNonEmptyResponse()
    {
        // FileSink returns empty, HttpSink returns the Worker's hook response. Composite should
        // propagate the HttpSink response so HookForwarder can write it to stdout.
        var fileSink = new CallbackSink(_ => Task.FromResult(string.Empty));
        var httpSink = new CallbackSink(_ => Task.FromResult("""{"hookSpecificOutput":{"additionalContext":"hi"}}"""));

        var composite = new CompositeSink(new[] { fileSink, httpSink });
        var response = await composite.ForwardAsync("{}", CancellationToken.None);

        response.Should().Be("""{"hookSpecificOutput":{"additionalContext":"hi"}}""");
    }

    [Fact]
    public async Task ForwardAsync_ReturnsEmptyWhenAllSinksReturnEmpty()
    {
        var a = new CallbackSink(_ => Task.FromResult(string.Empty));
        var b = new CallbackSink(_ => Task.FromResult(string.Empty));

        var composite = new CompositeSink(new[] { a, b });
        var response = await composite.ForwardAsync("{}", CancellationToken.None);

        response.Should().BeEmpty();
    }

    [Fact]
    public async Task ForwardAsync_SwallowsException_AndStillReturnsOtherSinkResponse()
    {
        // HttpSink throws (network failure), FileSink returns empty. Composite should not throw,
        // and should return empty (no non-empty response survived).
        var fileSink = new CallbackSink(_ => Task.FromResult(string.Empty));
        var httpSink = new CallbackSink(_ => throw new HttpRequestException("network down"));

        var composite = new CompositeSink(new[] { fileSink, httpSink });
        var response = await composite.ForwardAsync("{}", CancellationToken.None);

        response.Should().BeEmpty();
    }

    [Fact]
    public async Task ForwardAsync_PrefersFirstNonEmpty_WhenMultipleSinksRespond()
    {
        // If both sinks somehow return non-empty (shouldn't happen in practice, but contract
        // should still be deterministic), the FIRST non-empty wins.
        var a = new CallbackSink(_ => Task.FromResult("from-a"));
        var b = new CallbackSink(_ => Task.FromResult("from-b"));

        var composite = new CompositeSink(new[] { a, b });
        var response = await composite.ForwardAsync("{}", CancellationToken.None);

        response.Should().Be("from-a");
    }

    private sealed class CallbackSink : IAgentEventSink
    {
        private readonly Func<string, Task<string>> _onForward;
        public CallbackSink(Func<string, Task<string>> onForward) => _onForward = onForward;
        public Task<string> ForwardAsync(string envelopeJson, CancellationToken ct) => _onForward(envelopeJson);
    }
}
