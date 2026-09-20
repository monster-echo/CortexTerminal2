using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Membership;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class MembershipServiceRedeemTests
{
    private static async Task<(AppDbContext db, MembershipService svc, string userId, RedeemCode code)> SetupAsync(
        int maxUses = 1, DateTimeOffset? expires = null)
    {
        var factory = TestSessionFactory.CreateContextFactoryPublic();
        var db = await factory.CreateDbContextAsync();
        await PlanCatalog.SeedAsync(db, new MembershipOptions());
        var svc = new MembershipService(factory);
        var userId = Guid.NewGuid().ToString("N");
        db.Users.Add(new User { Id = userId, Username = $"u-{userId.Substring(0, 8)}", Role = "user", Status = "active", MembershipTier = MembershipTiers.Free, CreatedAtUtc = DateTimeOffset.UtcNow, UpdatedAtUtc = DateTimeOffset.UtcNow });
        var life = await db.Plans.SingleAsync(p => p.Code == PlanCodes.ProLifetime);
        var code = new RedeemCode
        {
            Code = "CORTERM-ABCD1234", PlanId = life.Id, BillingPeriod = BillingPeriods.Lifetime,
            MaxUses = maxUses, ExpiresAtUtc = expires, CreatedByUserId = "admin-1", IsActive = true,
        };
        db.RedeemCodes.Add(code);
        await db.SaveChangesAsync();
        return (db, svc, userId, code);
    }

    [Fact]
    public async Task RedeemAsync_ValidCode_GrantsPro()
    {
        var (db, svc, userId, code) = await SetupAsync();
        var sub = await svc.RedeemAsync(userId, code.Code, CancellationToken.None);
        sub.Status.Should().Be(SubscriptionStatuses.Active);
        (await db.Users.AsNoTracking().SingleAsync(u => u.Id == userId)).MembershipTier.Should().Be(MembershipTiers.Pro);
        var refreshed = await db.RedeemCodes.AsNoTracking().SingleAsync(c => c.Id == code.Id);
        refreshed.UsedCount.Should().Be(1);
    }

    [Fact]
    public async Task RedeemAsync_UnknownCode_ThrowsInvalid()
    {
        var (_, svc, userId, _) = await SetupAsync();
        var act = async () => await svc.RedeemAsync(userId, "NOPE", CancellationToken.None);
        await act.Should().ThrowAsync<RedeemCodeInvalidException>();
    }

    [Fact]
    public async Task RedeemAsync_ExpiredCode_ThrowsExpired()
    {
        var (_, svc, userId, code) = await SetupAsync(expires: DateTimeOffset.UtcNow.AddDays(-1));
        var act = async () => await svc.RedeemAsync(userId, code.Code, CancellationToken.None);
        await act.Should().ThrowAsync<RedeemCodeExpiredException>();
    }

    [Fact]
    public async Task RedeemAsync_ExhaustedCode_ThrowsExhausted()
    {
        var (db, svc, userId, code) = await SetupAsync(maxUses: 1);
        var other = Guid.NewGuid().ToString("N");
        db.Users.Add(new User { Id = other, Username = $"u-{other.Substring(0, 8)}", Role = "user", Status = "active", MembershipTier = MembershipTiers.Free, CreatedAtUtc = DateTimeOffset.UtcNow, UpdatedAtUtc = DateTimeOffset.UtcNow });
        await db.SaveChangesAsync();
        await svc.RedeemAsync(other, code.Code, CancellationToken.None);

        var act = async () => await svc.RedeemAsync(userId, code.Code, CancellationToken.None);
        await act.Should().ThrowAsync<RedeemCodeExhaustedException>();
    }

    [Fact]
    public async Task RedeemAsync_SameUserTwice_ThrowsAlreadyUsed()
    {
        var (_, svc, userId, code) = await SetupAsync(maxUses: 5);
        await svc.RedeemAsync(userId, code.Code, CancellationToken.None);
        var act = async () => await svc.RedeemAsync(userId, code.Code, CancellationToken.None);
        await act.Should().ThrowAsync<RedeemCodeAlreadyUsedException>();
    }
}
