using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Json;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Membership;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;
using CortexTerminal.Gateway.Tests.Auth;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class MembershipClaimTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;
    public MembershipClaimTests(GatewayApplicationFactory factory) => _factory = factory;

    [Fact]
    public async Task Refresh_AfterGrant_TokenCarriesProClaim()
    {
        var target = $"u-{Guid.NewGuid():N}".Substring(0, 12);
        await _factory.SeedAsync(async db =>
        {
            db.Users.Add(new User { Id = Guid.NewGuid().ToString("N"), Username = target, Role = "user", Status = "active", MembershipTier = MembershipTiers.Free, CreatedAtUtc = DateTimeOffset.UtcNow, UpdatedAtUtc = DateTimeOffset.UtcNow });
            await db.SaveChangesAsync();
        });
        // admin grants Pro
        using (var admin = _factory.CreateAdminClient())
        {
            var resp = await admin.PostAsJsonAsync("/api/admin/membership/grant", new { userId = target, planCode = PlanCodes.ProLifetime });
            resp.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
        }
        // user refreshes
        using var user = _factory.CreateAuthenticatedClient(target);
        var refreshResp = await user.PostAsync("/api/auth/refresh", null);
        refreshResp.StatusCode.Should().Be(System.Net.HttpStatusCode.OK);
        var refreshed = await refreshResp.Content.ReadFromJsonAsync<RefreshResponse>();
        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(refreshed!.AccessToken);
        jwt.Claims.Should().Contain(c => c.Type == "membership_tier" && c.Value == MembershipTiers.Pro);

        var sub = await user.GetFromJsonAsync<SubscriptionDto>("/api/billing/subscription");
        sub!.Tier.Should().Be(MembershipTiers.Pro);
        sub.IsActive.Should().BeTrue();
    }

    public sealed record RefreshResponse(string AccessToken);
    public sealed record SubscriptionDto(string Tier, string PlanCode, bool IsActive, DateTimeOffset? ExpiresAtUtc, int MaxWorkers, int MaxArtifactsPerSession, int MaxScrollbackMegabytes);
}
