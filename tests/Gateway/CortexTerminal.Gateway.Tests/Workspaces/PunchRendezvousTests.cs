using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Workspaces;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Workspaces;

public sealed class PunchRendezvousTests
{
    private sealed class FixedTime(DateTimeOffset now) : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = now;
        public override DateTimeOffset GetUtcNow() => Now;
    }

    private static readonly DateTimeOffset Start = new(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Register_FirstSide_NotReady()
    {
        var rendezvous = new PunchRendezvous(new FixedTime(Start));
        var result = rendezvous.Register("tid-1", PunchRole.Worker, "203.0.113.1:5000");

        result.Ready.Should().BeFalse();
        result.Peer.Should().BeNull();
    }

    [Fact]
    public void Register_BothSides_ReadyWithPeerEndpoint()
    {
        var rendezvous = new PunchRendezvous(new FixedTime(Start));
        rendezvous.Register("tid-1", PunchRole.Worker, "203.0.113.1:5000");

        var clientResult = rendezvous.Register("tid-1", PunchRole.Client, "198.51.100.9:6000");
        clientResult.Ready.Should().BeTrue();
        clientResult.Peer!.Endpoint.Should().Be("203.0.113.1:5000");

        var workerAgain = rendezvous.Register("tid-1", PunchRole.Worker, "203.0.113.1:5000");
        workerAgain.Ready.Should().BeTrue();
        workerAgain.Peer!.Endpoint.Should().Be("198.51.100.9:6000");
    }

    [Fact]
    public void Register_InvalidRole_Throws()
    {
        var rendezvous = new PunchRendezvous(new FixedTime(Start));
        var act = () => rendezvous.Register("tid-1", "middle", "1.2.3.4:5");
        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void Register_AfterWindowExpiry_StartsFreshRendezvous()
    {
        var clock = new FixedTime(Start);
        var rendezvous = new PunchRendezvous(clock);
        rendezvous.Register("tid-1", PunchRole.Worker, "203.0.113.1:5000");

        clock.Now = Start.AddSeconds(PunchRendezvous.WindowSeconds + 1);
        var fresh = rendezvous.Register("tid-1", PunchRole.Client, "198.51.100.9:6000");

        fresh.Ready.Should().BeFalse(); // 旧条目已过期，重新等待 worker 上报
    }
}
