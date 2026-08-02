using CortexTerminal.Gateway.Tunnels;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Tunnels;

public sealed class TunnelQuotaTests
{
    [Fact]
    public void TryAcquire_accepts_up_to_qps_within_same_second()
    {
        var quota = new TunnelQuota(
            new TunnelOptions { MaxQpsPerTunnel = 2 },
            new FakeTimeProvider(new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero)));

        quota.TryAcquire("t1").Should().BeTrue();
        quota.TryAcquire("t1").Should().BeTrue();
        quota.TryAcquire("t1").Should().BeFalse();
    }

    [Fact]
    public void TryAcquire_resets_in_next_window()
    {
        var clock = new FakeTimeProvider(new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero));
        var quota = new TunnelQuota(new TunnelOptions { MaxQpsPerTunnel = 2 }, clock);

        quota.TryAcquire("t1").Should().BeTrue();
        quota.TryAcquire("t1").Should().BeTrue();
        quota.TryAcquire("t1").Should().BeFalse();

        clock.Now = clock.Now.AddSeconds(1);

        quota.TryAcquire("t1").Should().BeTrue();
    }

    [Fact]
    public void TryAcquire_counts_per_tunnel_independently()
    {
        var quota = new TunnelQuota(
            new TunnelOptions { MaxQpsPerTunnel = 2 },
            new FakeTimeProvider(new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero)));

        quota.TryAcquire("t1").Should().BeTrue();
        quota.TryAcquire("t1").Should().BeTrue();
        quota.TryAcquire("t2").Should().BeTrue();
        quota.TryAcquire("t1").Should().BeFalse(); // t1 已超限
        quota.TryAcquire("t2").Should().BeTrue();  // t2 独立配额(count=2 ≤ 2)
        quota.TryAcquire("t2").Should().BeFalse(); // t2 现在超限
    }

    private sealed class FakeTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = now;

        public override DateTimeOffset GetUtcNow() => Now;

        public override long GetTimestamp() => Now.UtcTicks;
    }
}
