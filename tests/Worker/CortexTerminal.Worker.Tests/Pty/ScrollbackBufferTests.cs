using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Pty;
using FluentAssertions;
using System.Linq;

namespace CortexTerminal.Worker.Tests.Pty;

public sealed class ScrollbackBufferTests
{
    [Fact]
    public void Append_PreservesStdoutAndStderrOrder()
    {
        var buffer = new ScrollbackBuffer(1024);

        buffer.Append("sess_1", "stdout", [0x61]);
        buffer.Append("sess_1", "stderr", [0x62]);
        buffer.Append("sess_1", "stdout", [0x63]);

        AssertChunks(
            buffer.Snapshot(),
            ("sess_1", "stdout", [0x61]),
            ("sess_1", "stderr", [0x62]),
            ("sess_1", "stdout", [0x63]));
    }

    [Fact]
    public void Append_EvictsOldestChunksWhenOverLimit()
    {
        var buffer = new ScrollbackBuffer(5);

        buffer.Append("sess_1", "stdout", [0x61, 0x62]);
        buffer.Append("sess_1", "stderr", [0x63, 0x64, 0x65]);
        buffer.Append("sess_1", "stdout", [0x66, 0x67, 0x68, 0x69]);

        AssertChunks(buffer.Snapshot(), ("sess_1", "stdout", [0x66, 0x67, 0x68, 0x69]));
    }

    [Fact]
    public void Append_CopiesPayloadBeforeStoringSnapshot()
    {
        var buffer = new ScrollbackBuffer(1024);
        var payload = new byte[] { 0x61, 0x62 };

        buffer.Append("sess_1", "stdout", payload);
        payload[0] = 0x7A;
        payload[1] = 0x79;

        var snapshot = buffer.Snapshot();
        AssertChunks(snapshot, ("sess_1", "stdout", [0x61, 0x62]));
        snapshot.Single().Payload.Should().NotBeSameAs(payload);
    }

    private static void AssertChunks(
        IReadOnlyList<TerminalChunk> actual,
        params (string SessionId, string Stream, byte[] Payload)[] expected)
    {
        actual.Should().HaveCount(expected.Length);

        for (var i = 0; i < expected.Length; i++)
        {
            actual[i].SessionId.Should().Be(expected[i].SessionId);
            actual[i].Stream.Should().Be(expected[i].Stream);
            actual[i].Payload.Should().Equal(expected[i].Payload);
        }
    }
}
