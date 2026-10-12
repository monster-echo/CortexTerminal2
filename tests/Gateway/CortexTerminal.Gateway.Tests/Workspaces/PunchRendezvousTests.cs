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

    // ── Worker 锚点（key=workerId，常驻续约） ──────────────────────

    [Fact]
    public void Anchor_ClientBeforeWorker_NotReadyAndNoEntryCreated()
    {
        var rendezvous = new PunchRendezvous(new FixedTime(Start));

        var result = rendezvous.RegisterAnchorClient("worker-1", "198.51.100.9:6000", "tid-1", "tok-1");

        // worker 锚点不存在：客户端立即回落 Relay，且不留下空条目
        result.HasClient.Should().BeFalse();
        result.Client.Should().BeNull();
    }

    [Fact]
    public void Anchor_WorkerThenClient_ClientReceivesWorkerEndpoint()
    {
        var clock = new FixedTime(Start);
        var rendezvous = new PunchRendezvous(clock);

        var anchor = rendezvous.RegisterAnchor("worker-1", "203.0.113.1:5000");
        anchor.HasClient.Should().BeFalse();

        var client = rendezvous.RegisterAnchorClient("worker-1", "198.51.100.9:6000", "tid-1", "tok-1");
        client.HasClient.Should().BeTrue();
        client.Client!.Endpoint.Should().Be("203.0.113.1:5000");

        // worker 下一次续约取走客户端信封（端点 + transferId + relayToken）
        var refresh = rendezvous.RegisterAnchor("worker-1", "203.0.113.1:5000");
        refresh.HasClient.Should().BeTrue();
        refresh.Client!.Endpoint.Should().Be("198.51.100.9:6000");
        refresh.TransferId.Should().Be("tid-1");
        refresh.RelayToken.Should().Be("tok-1");
    }

    [Fact]
    public void Anchor_ClientEnvelope_StaleAfterFreshnessWindow()
    {
        var clock = new FixedTime(Start);
        var rendezvous = new PunchRendezvous(clock);
        rendezvous.RegisterAnchor("worker-1", "203.0.113.1:5000");
        rendezvous.RegisterAnchorClient("worker-1", "198.51.100.9:6000", "tid-1", "tok-1");

        // 客户端注册超 freshness 窗口仍未被 worker 取走 → 信封作废，
        // 但 worker 锚点本身随续约继续有效
        clock.Now = Start.AddSeconds(PunchRendezvous.AnchorClientFreshSeconds + 1);
        var refresh = rendezvous.RegisterAnchor("worker-1", "203.0.113.1:5000");

        refresh.HasClient.Should().BeFalse();
        refresh.TransferId.Should().BeNull();
    }

    [Fact]
    public void Anchor_WithoutWorkerRefresh_EntryExpiresAndClientStartsClean()
    {
        var clock = new FixedTime(Start);
        var rendezvous = new PunchRendezvous(clock);
        rendezvous.RegisterAnchor("worker-1", "203.0.113.1:5000");
        rendezvous.RegisterAnchorClient("worker-1", "198.51.100.9:6000", "tid-1", "tok-1");

        clock.Now = Start.AddSeconds(PunchRendezvous.AnchorTtlSeconds + 1);
        var client = rendezvous.RegisterAnchorClient("worker-1", "198.51.100.9:6000", "tid-2", "tok-2");

        client.HasClient.Should().BeFalse(); // 锚点断连过期：客户端立即回落 Relay
    }
}
