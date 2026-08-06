using CortexTerminal.Gateway.Data;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class UserMembershipFieldsTests
{
    [Fact]
    public void User_DefaultTier_IsFree()
    {
        var u = new User();
        u.MembershipTier.Should().Be("free");
        u.MembershipPlanId.Should().BeNull();
        u.MembershipExpiresAtUtc.Should().BeNull();
    }
}
