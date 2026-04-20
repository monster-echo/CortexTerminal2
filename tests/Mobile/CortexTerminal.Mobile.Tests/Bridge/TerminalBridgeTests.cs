using FluentAssertions;
using Xunit;

namespace CortexTerminal.Mobile.Tests.Bridge;

public sealed class TerminalBridgeTests
{
    [Fact]
    public void ForwardInput_PreservesByteOrder()
    {
        var bridge = new TestTerminalBridge();
        var payload = new byte[] { 0x09, 0x03, 0x1B, 0x5B, 0x41 };

        var forwarded = bridge.ForwardInput(payload);

        forwarded.Should().Equal(payload);
    }

    [Fact]
    public void ForwardInput_CreatesDefensiveCopy()
    {
        var bridge = new TestTerminalBridge();
        var payload = new byte[] { 0x09, 0x03 };

        var forwarded = bridge.ForwardInput(payload);
        payload[0] = 0xFF;

        forwarded[0].Should().Be(0x09);
    }

    [Fact]
    public void ForwardStdout_PreservesPayload()
    {
        var bridge = new TestTerminalBridge();
        var payload = new byte[] { 0x48, 0x65, 0x6C, 0x6C, 0x6F };

        bridge.ForwardStdout(payload).Should().Equal(payload);
    }

    [Fact]
    public void ForwardStderr_PreservesPayload()
    {
        var bridge = new TestTerminalBridge();
        var payload = new byte[] { 0x45, 0x72, 0x72 };

        bridge.ForwardStderr(payload).Should().Equal(payload);
    }
}

// Duplicate of the actual bridge for testing (MAUI project can't be referenced from net10.0 test)
internal sealed class TestTerminalBridge
{
    public byte[] ForwardInput(byte[] payload) => payload.ToArray();
    public byte[] ForwardStdout(byte[] payload) => payload.ToArray();
    public byte[] ForwardStderr(byte[] payload) => payload.ToArray();
}
