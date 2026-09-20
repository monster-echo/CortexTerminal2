using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Membership;
using CortexTerminal.Gateway.Membership.Iap;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class MembershipServiceIapGrantTests
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

    private static AppleVerifiedTransaction Tx(string productId, long? expiresMs, string txId = "orig-1") =>
        new(txId, productId, expiresMs, "Auto-Renewable Subscription");

    [Fact]
    public async Task GrantFromIapAsync_Monthly_SetsExpiryFromTransaction()
    {
        var (db, svc, userId) = await SetupAsync();
        var expires = new DateTimeOffset(2026, 12, 31, 0, 0, 0, TimeSpan.Zero);
        var verified = Tx(AppleProductIds.ProMonth, expires.ToUnixTimeMilliseconds());

        var sub = await svc.GrantFromIapAsync(userId, verified, OrderChannels.IapApple, CancellationToken.None);

        sub.Status.Should().Be(SubscriptionStatuses.Active);
        sub.Source.Should().Be(SubscriptionSources.IapApple);
        sub.PlatformTransactionId.Should().Be("orig-1");
        sub.ExpiresAtUtc.Should().NotBeNull();
        sub.ExpiresAtUtc!.Value.ToUnixTimeMilliseconds().Should().Be(expires.ToUnixTimeMilliseconds());
        var u = await db.Users.AsNoTracking().SingleAsync(x => x.Id == userId);
        u.MembershipTier.Should().Be(MembershipTiers.Pro);
    }

    [Fact]
    public async Task GrantFromIapAsync_Lifetime_NoExpiry()
    {
        var (db, svc, userId) = await SetupAsync();
        var verified = Tx(AppleProductIds.ProLifetime, null);

        var sub = await svc.GrantFromIapAsync(userId, verified, OrderChannels.IapApple, CancellationToken.None);

        sub.ExpiresAtUtc.Should().BeNull();
        var u = await db.Users.AsNoTracking().SingleAsync(x => x.Id == userId);
        u.MembershipExpiresAtUtc.Should().BeNull();
        u.MembershipTier.Should().Be(MembershipTiers.Pro);
    }

    [Fact]
    public async Task GrantFromIapAsync_DuplicateTransactionId_IsIdempotent()
    {
        var (db, svc, userId) = await SetupAsync();
        var verified = Tx(AppleProductIds.ProYear, new DateTimeOffset(2027, 1, 1, 0, 0, 0, TimeSpan.Zero).ToUnixTimeMilliseconds(), "dup-1");

        var first = await svc.GrantFromIapAsync(userId, verified, OrderChannels.IapApple, CancellationToken.None);
        var second = await svc.GrantFromIapAsync(userId, verified, OrderChannels.IapApple, CancellationToken.None);

        second.Id.Should().Be(first.Id);
        var orderCount = await db.MembershipOrders.AsNoTracking().CountAsync(o => o.UserId == userId);
        orderCount.Should().Be(1, "duplicate verify must not create a second order");
    }

    [Fact]
    public async Task GrantFromIapAsync_UnknownProductId_Throws()
    {
        var (_, svc, userId) = await SetupAsync();
        var verified = Tx("corterm.unknown", null);
        var act = async () => await svc.GrantFromIapAsync(userId, verified, OrderChannels.IapApple, CancellationToken.None);
        await act.Should().ThrowAsync<ArgumentException>();
    }
}
