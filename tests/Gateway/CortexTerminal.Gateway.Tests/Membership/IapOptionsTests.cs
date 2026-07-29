using CortexTerminal.Gateway.Membership;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class IapOptionsTests
{
    [Fact]
    public void IapOptions_HasAppleDefaults()
    {
        var opts = new IapOptions();
        opts.Apple.Should().NotBeNull();
        opts.Apple.BundleId.Should().BeEmpty();
        opts.Apple.Environment.Should().Be("Production");
    }

    [Theory]
    [InlineData(AppleProductIds.ProMonth, PlanCodes.ProMonth)]
    [InlineData(AppleProductIds.ProYear, PlanCodes.ProYear)]
    [InlineData(AppleProductIds.ProLifetime, PlanCodes.ProLifetime)]
    [InlineData("corterm.unknown", null)]
    public void ToPlanCode_MapsAppleProductId(string productId, string? expected)
    {
        AppleProductIds.ToPlanCode(productId).Should().Be(expected);
    }
}
