using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Membership;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class MembershipServiceGrantTests
{
    private static async Task<(AppDbContext db, MembershipService svc, string userId)> SetupAsync()
    {
        var factory = TestSessionFactory.CreateContextFactoryPublic();
        var db = await factory.CreateDbContextAsync();
        await PlanCatalog.SeedAsync(db, new MembershipOptions());
        var svc = new MembershipService(factory);
        var userId = Guid.NewGuid().ToString("N");
        db.Users.Add(new User { Id = userId, Username = $"u-{userId.Substring(0, 8)}", Role = "user", Status = "active", MembershipTier = MembershipTiers.Free, CreatedAtUtc = DateTimeOffset.UtcNow, UpdatedAtUtc = DateTimeOffset.UtcNow });
        await db.SaveChangesAsync();
        return (db, svc, userId);
    }

    [Fact]
    public async Task GrantAsync_LifetimePlan_SetsProWithNoExpiry()
    {
        var (db, svc, userId) = await SetupAsync();
        var life = await db.Plans.SingleAsync(p => p.Code == PlanCodes.ProLifetime);

        var sub = await svc.GrantAsync(userId, life.Id, OrderChannels.Manual, expiresAtUtc: null,
            grantedByUserId: "admin-1", sourceRedeemCodeId: null, ct: CancellationToken.None);

        sub.Status.Should().Be(SubscriptionStatuses.Active);
        sub.ExpiresAtUtc.Should().BeNull();
        sub.Source.Should().Be(SubscriptionSources.ManualGrant);
        var u = await db.Users.AsNoTracking().SingleAsync(x => x.Id == userId);
        u.MembershipTier.Should().Be(MembershipTiers.Pro);
        u.MembershipExpiresAtUtc.Should().BeNull();
        var order = await db.MembershipOrders.AsNoTracking().SingleAsync(o => o.UserId == userId);
        order.Channel.Should().Be(OrderChannels.Manual);
        order.Status.Should().Be(OrderStatuses.Completed);
    }

    [Fact]
    public async Task GrantAsync_YearlyPlan_SetsExpiryOneYearOut()
    {
        var (db, svc, userId) = await SetupAsync();
        var year = await db.Plans.SingleAsync(p => p.Code == PlanCodes.ProYear);

        var sub = await svc.GrantAsync(userId, year.Id, OrderChannels.Manual, expiresAtUtc: null,
            grantedByUserId: "admin-1", sourceRedeemCodeId: null, ct: CancellationToken.None);

        sub.ExpiresAtUtc.Should().NotBeNull();
        (sub.ExpiresAtUtc!.Value - DateTimeOffset.UtcNow).TotalDays.Should().BeGreaterThan(360);
    }
}
