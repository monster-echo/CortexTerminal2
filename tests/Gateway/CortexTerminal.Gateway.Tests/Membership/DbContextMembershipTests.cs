using CortexTerminal.Gateway.Data;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class DbContextMembershipTests
{
    [Fact]
    public async Task DbContext_HasAllMembershipDbSets()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase($"membership_db_{Guid.NewGuid():N}").Options;
        await using var db = new AppDbContext(options);

        (await db.Plans.AnyAsync()).Should().BeFalse();
        (await db.Subscriptions.AnyAsync()).Should().BeFalse();
        (await db.MembershipOrders.AnyAsync()).Should().BeFalse();
        (await db.RedeemCodes.AnyAsync()).Should().BeFalse();
        (await db.RedeemCodeUsages.AnyAsync()).Should().BeFalse();
        (await db.IapWebhookEvents.AnyAsync()).Should().BeFalse();
    }
}
