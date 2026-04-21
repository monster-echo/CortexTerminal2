using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Pty;
using FluentAssertions;

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

        buffer.Snapshot().Should().Equal(new[]
        {
            new TerminalChunk("sess_1", "stdout", [0x61]),
            new TerminalChunk("sess_1", "stderr", [0x62]),
            new TerminalChunk("sess_1", "stdout", [0x63])
        });
    }

    [Fact]
    public void Append_EvictsOldestChunksWhenOverLimit()
    {
        var buffer = new ScrollbackBuffer(5);

        buffer.Append("sess_1", "stdout", [0x61, 0x62]);
        buffer.Append("sess_1", "stderr", [0x63, 0x64, 0x65]);
        buffer.Append("sess_1", "stdout", [0x66, 0x67, 0x68, 0x69]);

        buffer.Snapshot().Should().Equal(new[]
        {
            new TerminalChunk("sess_1", "stdout", [0x66, 0x67, 0x68, 0x69])
        });
    }
}
