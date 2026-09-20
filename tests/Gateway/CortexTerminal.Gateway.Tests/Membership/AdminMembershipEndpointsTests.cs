using System.Net;
using System.Net.Http.Json;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Membership;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;
using CortexTerminal.Gateway.Tests.Auth;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class AdminMembershipEndpointsTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;
    public AdminMembershipEndpointsTests(GatewayApplicationFactory factory) => _factory = factory;

    [Fact]
    public async Task Grant_NonAdmin_Forbidden()
    {
        var username = $"u-{Guid.NewGuid():N}".Substring(0, 12);
        await _factory.SeedAsync(async db =>
        {
            db.Users.Add(new User { Id = Guid.NewGuid().ToString("N"), Username = username, Role = "user", Status = "active", MembershipTier = MembershipTiers.Free, CreatedAtUtc = DateTimeOffset.UtcNow, UpdatedAtUtc = DateTimeOffset.UtcNow });
            await db.SaveChangesAsync();
        });
        using var client = _factory.CreateAuthenticatedClient(username);
        var resp = await client.PostAsJsonAsync("/api/admin/membership/grant", new { userId = "x", planCode = PlanCodes.ProLifetime });
        resp.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Grant_Admin_UpgradeUserToPro()
    {
        var target = $"u-{Guid.NewGuid():N}".Substring(0, 12);
        await _factory.SeedAsync(async db =>
        {
            db.Users.Add(new User { Id = Guid.NewGuid().ToString("N"), Username = target, Role = "user", Status = "active", MembershipTier = MembershipTiers.Free, CreatedAtUtc = DateTimeOffset.UtcNow, UpdatedAtUtc = DateTimeOffset.UtcNow });
            await db.SaveChangesAsync();
        });
        using var client = _factory.CreateAdminClient();
        var resp = await client.PostAsJsonAsync("/api/admin/membership/grant", new { userId = target, planCode = PlanCodes.ProYear });
        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        var saved = await _factory.QueryAsync(db => db.Users.AsNoTracking().FirstAsync(u => u.Username == target));
        saved.MembershipTier.Should().Be(MembershipTiers.Pro);
    }

    [Fact]
    public async Task GenerateCodes_Admin_CreatesBatch()
    {
        using var client = _factory.CreateAdminClient();
        var resp = await client.PostAsJsonAsync("/api/admin/redeem-codes", new { planCode = PlanCodes.ProLifetime, count = 3 });
        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await resp.Content.ReadFromJsonAsync<GenerateCodesResponse>();
        body!.Codes.Should().HaveCount(3);
        body.Codes.Should().OnlyContain(c => c == c.ToUpperInvariant());
    }

    public sealed record GenerateCodesResponse(IReadOnlyList<string> Codes);
}
