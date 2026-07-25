using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Membership;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class EntitlementServiceTests
{
    private static async Task<(AppDbContext db, EntitlementService svc)> SetupAsync()
    {
        var factory = TestSessionFactory.CreateContextFactoryPublic();
        var db = await factory.CreateDbContextAsync();
        await PlanCatalog.SeedAsync(db, new MembershipOptions());
        var svc = new EntitlementService(factory, NullLogger<EntitlementService>.Instance);
        return (db, svc);
    }

    private static async Task<string> SeedUserAsync(AppDbContext db, string tier = MembershipTiers.Free,
        DateTimeOffset? expires = null, string? planId = null)
    {
        var id = Guid.NewGuid().ToString("N");
        db.Users.Add(new User
        {
            Id = id, Username = $"u-{id.Substring(0, 8)}",
            Role = "user", Status = "active",
            MembershipTier = tier, MembershipPlanId = planId, MembershipExpiresAtUtc = expires,
            CreatedAtUtc = DateTimeOffset.UtcNow, UpdatedAtUtc = DateTimeOffset.UtcNow,
        });
        await db.SaveChangesAsync();
        return id;
    }

    [Fact]
    public async Task GetEntitlementAsync_FreeUser_ReturnsFreeQuotas()
    {
        var (db, svc) = await SetupAsync();
        var userId = await SeedUserAsync(db);
        var free = await db.Plans.SingleAsync(p => p.Code == PlanCodes.Free);

        var e = await svc.GetEntitlementAsync(userId, CancellationToken.None);

        e.Tier.Should().Be(MembershipTiers.Free);
        e.MaxWorkers.Should().Be(free.MaxWorkers);
        e.IsActive.Should().BeFalse();
    }

    [Fact]
    public async Task GetEntitlementAsync_ProUser_ReturnsProQuotas()
    {
        var (db, svc) = await SetupAsync();
        var pro = await db.Plans.SingleAsync(p => p.Code == PlanCodes.ProYear);
        var userId = await SeedUserAsync(db, MembershipTiers.Pro, expires: DateTimeOffset.UtcNow.AddDays(30), planId: pro.Id);

        var e = await svc.GetEntitlementAsync(userId, CancellationToken.None);

        e.Tier.Should().Be(MembershipTiers.Pro);
        e.MaxWorkers.Should().Be(pro.MaxWorkers);
        e.IsActive.Should().BeTrue();
    }

    [Fact]
    public async Task GetEntitlementAsync_ExpiredPro_LazilyDegradesToFree()
    {
        var (db, svc) = await SetupAsync();
        var pro = await db.Plans.SingleAsync(p => p.Code == PlanCodes.ProMonth);
        var userId = await SeedUserAsync(db, MembershipTiers.Pro,
            expires: DateTimeOffset.UtcNow.AddDays(-1), planId: pro.Id);

        var e = await svc.GetEntitlementAsync(userId, CancellationToken.None);

        e.Tier.Should().Be(MembershipTiers.Free);
        e.IsActive.Should().BeFalse();
        // The service writes on its own DbContext. The InMemory provider backs both with a
        // shared store by name; AsNoTracking bypasses this test context's stale local cache.
        var refreshed = await db.Users.AsNoTracking().SingleAsync(u => u.Id == userId);
        refreshed.MembershipTier.Should().Be(MembershipTiers.Free);
    }

    [Fact]
    public async Task GetEntitlementAsync_LifetimePro_NeverExpires()
    {
        var (db, svc) = await SetupAsync();
        var life = await db.Plans.SingleAsync(p => p.Code == PlanCodes.ProLifetime);
        var userId = await SeedUserAsync(db, MembershipTiers.Pro, expires: null, planId: life.Id);

        var e = await svc.GetEntitlementAsync(userId, CancellationToken.None);

        e.IsActive.Should().BeTrue();
        e.ExpiresAtUtc.Should().BeNull();
    }
}
