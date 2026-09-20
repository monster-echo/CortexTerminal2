using CortexTerminal.Gateway.Membership;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class CodesTests
{
    [Fact]
    public void Tiers_AreLowerCaseStrings()
    {
        MembershipTiers.Free.Should().Be("free");
        MembershipTiers.Pro.Should().Be("pro");
    }

    [Fact]
    public void PlanCodes_CoverFreeAndThreeProSkus()
    {
        PlanCodes.Free.Should().Be("free");
        PlanCodes.ProMonth.Should().Be("pro_month");
        PlanCodes.ProYear.Should().Be("pro_year");
        PlanCodes.ProLifetime.Should().Be("pro_lifetime");
    }
}
