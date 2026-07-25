using System.Net;
using System.Net.Http.Json;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Membership;
using CortexTerminal.Gateway.Tests.Auth;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class BillingEndpointsTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;
    public BillingEndpointsTests(GatewayApplicationFactory factory) => _factory = factory;

    [Fact]
    public async Task GetPlans_IsAnonymous_AndReturnsFourPlans()
    {
        using var client = _factory.CreateClient();
        var plans = await client.GetFromJsonAsync<List<PlanDto>>("/api/billing/plans");
        plans.Should().NotBeNull();
        plans!.Select(p => p.Code).Should().Contain(new[] { "free", "pro_month", "pro_year", "pro_lifetime" });
    }

    [Fact]
    public async Task GetSubscription_ReturnsCurrentUserEntitlement()
    {
        var username = await SeedUserAsync();
        using var client = _factory.CreateAuthenticatedClient(username);
        var sub = await client.GetFromJsonAsync<SubscriptionDto>("/api/billing/subscription");
        sub!.Tier.Should().Be("free");
        sub.IsActive.Should().BeFalse();
    }

    private async Task<string> SeedUserAsync()
    {
        var username = $"u-{Guid.NewGuid():N}".Substring(0, 12);
        await _factory.SeedAsync(async db =>
        {
            db.Users.Add(new User { Id = Guid.NewGuid().ToString("N"), Username = username, Role = "user", Status = "active", MembershipTier = MembershipTiers.Free, CreatedAtUtc = DateTimeOffset.UtcNow, UpdatedAtUtc = DateTimeOffset.UtcNow });
            await db.SaveChangesAsync();
        });
        return username;
    }

    [Fact]
    public async Task Redeem_ValidCode_UpgradeToPro()
    {
        var username = $"u-{Guid.NewGuid():N}".Substring(0, 12);
        await _factory.SeedAsync(async db =>
        {
            db.Users.Add(new User { Id = Guid.NewGuid().ToString("N"), Username = username, Role = "user", Status = "active", MembershipTier = MembershipTiers.Free, CreatedAtUtc = DateTimeOffset.UtcNow, UpdatedAtUtc = DateTimeOffset.UtcNow });
            var life = await db.Plans.SingleAsync(p => p.Code == PlanCodes.ProLifetime);
            db.RedeemCodes.Add(new RedeemCode { Code = "CORTERM-XYZ12345", PlanId = life.Id, BillingPeriod = BillingPeriods.Lifetime, MaxUses = 1, CreatedByUserId = "admin", IsActive = true });
            await db.SaveChangesAsync();
        });
        using var client = _factory.CreateAuthenticatedClient(username);
        var resp = await client.PostAsJsonAsync("/api/billing/redeem", new { code = "CORTERM-XYZ12345" });
        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await resp.Content.ReadFromJsonAsync<RedeemResponse>();
        body!.Tier.Should().Be("pro");
    }

    [Fact]
    public async Task Redeem_InvalidCode_Returns400()
    {
        var username = $"u-{Guid.NewGuid():N}".Substring(0, 12);
        await _factory.SeedAsync(async db =>
        {
            db.Users.Add(new User { Id = Guid.NewGuid().ToString("N"), Username = username, Role = "user", Status = "active", MembershipTier = MembershipTiers.Free, CreatedAtUtc = DateTimeOffset.UtcNow, UpdatedAtUtc = DateTimeOffset.UtcNow });
            await db.SaveChangesAsync();
        });
        using var client = _factory.CreateAuthenticatedClient(username);
        var resp = await client.PostAsJsonAsync("/api/billing/redeem", new { code = "NOPE" });
        resp.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    public sealed record PlanDto(string Code, string Tier, string BillingPeriod, decimal PriceAmount, string PriceCurrency, int MaxWorkers, int MaxArtifactsPerSession, int MaxScrollbackMegabytes);
    public sealed record SubscriptionDto(string Tier, string PlanCode, bool IsActive, DateTimeOffset? ExpiresAtUtc, int MaxWorkers, int MaxArtifactsPerSession, int MaxScrollbackMegabytes);
    public sealed record RedeemResponse(string Tier, string PlanCode, bool IsActive);
}
