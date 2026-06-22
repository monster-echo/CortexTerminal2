using CortexTerminal.Gateway.Stats;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Stats;

public sealed class SessionStatsServiceTests
{
    private static SessionStatsService CreateService()
    {
        var services = new ServiceCollection();
        var provider = services.BuildServiceProvider();
        var scopeFactory = provider.GetRequiredService<IServiceScopeFactory>();
        return new SessionStatsService(scopeFactory);
    }

    [Fact]
    public void RecordBytes_AccumulatesSessionBytes()
    {
        var svc = CreateService();

        svc.RecordBytes("session-1", "user-1", 100);
        svc.RecordBytes("session-1", "user-1", 50);

        svc.GetSessionBytes("session-1").Should().Be(150);
    }

    [Fact]
    public void RecordBytes_AccumulatesUserBytes()
    {
        var svc = CreateService();

        svc.RecordBytes("session-1", "user-1", 100);
        svc.RecordBytes("session-2", "user-1", 50);

        svc.GetUserBytes("user-1").Should().Be(150);
    }

    [Fact]
    public void RecordBytes_DoesNotCrossSessions()
    {
        var svc = CreateService();

        svc.RecordBytes("session-1", "user-1", 100);
        svc.RecordBytes("session-2", "user-2", 200);

        svc.GetSessionBytes("session-1").Should().Be(100);
        svc.GetSessionBytes("session-2").Should().Be(200);
        svc.GetUserBytes("user-1").Should().Be(100);
        svc.GetUserBytes("user-2").Should().Be(200);
    }

    [Fact]
    public void GetSessionBytes_UnknownKey_ReturnsZero()
    {
        var svc = CreateService();

        svc.GetSessionBytes("nonexistent").Should().Be(0);
    }

    [Fact]
    public void GetUserBytes_UnknownKey_ReturnsZero()
    {
        var svc = CreateService();

        svc.GetUserBytes("nonexistent").Should().Be(0);
    }

    [Fact]
    public void RecordBytes_ZeroByteCount_DoesNotAccumulate()
    {
        var svc = CreateService();

        svc.RecordBytes("session-1", "user-1", 0);
        svc.RecordBytes("session-1", "user-1", -1);

        svc.GetSessionBytes("session-1").Should().Be(0);
        svc.GetUserBytes("user-1").Should().Be(0);
    }

    [Fact]
    public void GetAllSessionBytes_ReturnsAllKeys()
    {
        var svc = CreateService();

        svc.RecordBytes("session-1", "user-1", 10);
        svc.RecordBytes("session-2", "user-1", 20);

        var all = svc.GetAllSessionBytes();
        all.Should().HaveCount(2);
        all["session-1"].Should().Be(10);
        all["session-2"].Should().Be(20);
    }

    [Fact]
    public void GetAllUserBytes_ReturnsAllKeys()
    {
        var svc = CreateService();

        svc.RecordBytes("session-1", "user-1", 10);
        svc.RecordBytes("session-2", "user-2", 20);

        var all = svc.GetAllUserBytes();
        all.Should().HaveCount(2);
        all["user-1"].Should().Be(10);
        all["user-2"].Should().Be(20);
    }
}
