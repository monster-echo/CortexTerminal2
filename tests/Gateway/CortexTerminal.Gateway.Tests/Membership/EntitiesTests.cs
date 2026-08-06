using CortexTerminal.Gateway.Data;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class EntitiesTests
{
    [Fact]
    public void Subscription_Defaults()
    {
        var s = new Subscription();
        s.Id.Should().NotBeNullOrWhiteSpace();
        s.Status.Should().Be("active");
        s.ExpiresAtUtc.Should().BeNull();
        s.PlatformTransactionId.Should().BeNull();
    }

    [Fact]
    public void RedeemCode_Defaults()
    {
        var c = new RedeemCode();
        c.MaxUses.Should().Be(1);
        c.UsedCount.Should().Be(0);
        c.IsActive.Should().BeTrue();
    }

    [Fact]
    public void MembershipOrder_Defaults()
    {
        var o = new MembershipOrder();
        o.Status.Should().Be("created");
        o.Receipt.Should().BeNull();
        o.ProviderOrderId.Should().BeNull();
    }

    [Fact]
    public void IapWebhookEvent_Defaults()
    {
        var e = new IapWebhookEvent();
        e.Processed.Should().BeFalse();
    }
}
