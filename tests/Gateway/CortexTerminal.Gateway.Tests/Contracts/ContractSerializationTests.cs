using FluentAssertions;
using MessagePack;
using CortexTerminal.Contracts.Auth;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Contracts;

public sealed class ContractSerializationTests
{
    [Fact]
    public void WriteInputFrame_RoundTrips_WithRawBytes()
    {
        var frame = new WriteInputFrame("s-123", new byte[] { 0x09, 0x03, 0x1B, 0x41 });
        var bytes = MessagePackSerializer.Serialize(frame);
        var clone = MessagePackSerializer.Deserialize<WriteInputFrame>(bytes);

        clone.SessionId.Should().Be("s-123");
        clone.Payload.Should().Equal(0x09, 0x03, 0x1B, 0x41);
    }

    [Fact]
    public void TerminalChunk_RoundTrips_WithRawBytes()
    {
        var frame = new TerminalChunk("s-123", "stdout", new byte[] { 0x48, 0x69 });
        var clone = RoundTrip(frame);

        clone.SessionId.Should().Be("s-123");
        clone.Stream.Should().Be("stdout");
        clone.Payload.Should().Equal(0x48, 0x69);
    }

    [Fact]
    public void SessionStarted_RoundTrips()
    {
        var frame = new SessionStarted("s-123", 120, 40);
        var clone = RoundTrip(frame);

        clone.Should().Be(frame);
    }

    [Fact]
    public void SessionExited_RoundTrips()
    {
        var frame = new SessionExited("s-123", 0, "completed");
        var clone = RoundTrip(frame);

        clone.Should().Be(frame);
    }

    [Fact]
    public void WorkerUnavailableEvent_RoundTrips()
    {
        var frame = new WorkerUnavailableEvent("r-1", "no workers available");
        var clone = RoundTrip(frame);

        clone.Should().Be(frame);
    }

    [Fact]
    public void AuthExpiredEvent_RoundTrips()
    {
        var frame = new AuthExpiredEvent("r-2");
        var clone = RoundTrip(frame);

        clone.Should().Be(frame);
    }

    [Fact]
    public void SessionStartFailedEvent_RoundTrips()
    {
        var frame = new SessionStartFailedEvent("s-123", "pty failed");
        var clone = RoundTrip(frame);

        clone.Should().Be(frame);
    }

    [Fact]
    public void CreateSessionRequest_RoundTrips()
    {
        var frame = new CreateSessionRequest("shell", 120, 40);
        var clone = RoundTrip(frame);

        clone.Should().Be(frame);
    }

    [Fact]
    public void CreateSessionResponse_RoundTrips()
    {
        var frame = new CreateSessionResponse("s-123", "w-456");
        var clone = RoundTrip(frame);

        clone.Should().Be(frame);
    }

    [Fact]
    public void ResizePtyRequest_RoundTrips()
    {
        var frame = new ResizePtyRequest("s-123", 140, 50);
        var clone = RoundTrip(frame);

        clone.Should().Be(frame);
    }

    [Fact]
    public void CloseSessionRequest_RoundTrips()
    {
        var frame = new CloseSessionRequest("s-123");
        var clone = RoundTrip(frame);

        clone.Should().Be(frame);
    }

    [Fact]
    public void ReattachSessionRequest_RoundTrips_WithMessagePack()
    {
        var frame = new ReattachSessionRequest("s-123");
        var clone = RoundTrip(frame);

        clone.Should().Be(frame);
    }

    [Fact]
    public void ReplayChunk_RoundTrips_WithRawBytes()
    {
        var frame = new ReplayChunk("s-123", "stdout", new byte[] { 0x48, 0x69 });
        var clone = RoundTrip(frame);

        clone.SessionId.Should().Be("s-123");
        clone.Stream.Should().Be("stdout");
        clone.Payload.Should().Equal(0x48, 0x69);
    }

    [Fact]
    public void CreateSessionResult_RoundTrips()
    {
        var frame = CreateSessionResult.Success(new CreateSessionResponse("s-123", "w-456"));
        var clone = RoundTrip(frame);

        clone.IsSuccess.Should().BeTrue();
        clone.Response.Should().BeEquivalentTo(frame.Response);
        clone.ErrorCode.Should().BeNull();
    }

    [Fact]
    public void CreateSessionResult_Failure_RoundTrips()
    {
        var frame = CreateSessionResult.Failure("no-worker-available");
        var clone = RoundTrip(frame);

        clone.IsSuccess.Should().BeFalse();
        clone.Response.Should().BeNull();
        clone.ErrorCode.Should().Be("no-worker-available");
    }

    [Fact]
    public void DeviceFlowStartResponse_RoundTrips()
    {
        var frame = new DeviceFlowStartResponse("dc", "uc", "https://example.com", 600, 5);
        var clone = RoundTrip(frame);

        clone.Should().Be(frame);
    }

    [Fact]
    public void DeviceFlowTokenResponse_RoundTrips()
    {
        var frame = new DeviceFlowTokenResponse("at", "rt", 3600);
        var clone = RoundTrip(frame);

        clone.Should().Be(frame);
    }

    private static T RoundTrip<T>(T value)
        => MessagePackSerializer.Deserialize<T>(MessagePackSerializer.Serialize(value));
}
