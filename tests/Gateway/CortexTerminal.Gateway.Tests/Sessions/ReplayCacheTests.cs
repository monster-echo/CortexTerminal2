using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Sessions;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Sessions;

public sealed class ReplayCacheTests
{
    [Fact]
    public void Append_WhenMaxBytesExceeded_EvictsOldestChunksForSession()
    {
        var cache = new ReplayCache(5);
        var oldest = new ReplayChunk("session-1", "stdout", new byte[] { 0x01, 0x02 });
        var retained = new ReplayChunk("session-1", "stdout", new byte[] { 0x03, 0x04 });
        var newest = new ReplayChunk("session-1", "stderr", new byte[] { 0x05, 0x06, 0x07 });

        cache.Append(oldest);
        cache.Append(retained);
        cache.Append(newest);

        var snapshot = cache.GetSnapshot("session-1");

        snapshot.Should().Equal(retained, newest);
        snapshot.Sum(chunk => chunk.Payload.Length).Should().BeLessThanOrEqualTo(5);
    }
}
