using System.Net.Http.Json;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Membership;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;
using CortexTerminal.Gateway.Tests.Auth;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class ProfileScrollbackEntitlementTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;
    public ProfileScrollbackEntitlementTests(GatewayApplicationFactory factory) => _factory = factory;

    [Fact]
    public async Task Profile_FreeUser_ScrollbackMaxAllowedBytesMatchesFreeTier()
    {
        var username = $"u-{Guid.NewGuid():N}".Substring(0, 12);
        int freeMb = 0;
        await _factory.SeedAsync(async db =>
        {
            db.Users.Add(new User { Id = Guid.NewGuid().ToString("N"), Username = username, Role = "user", Status = "active", MembershipTier = MembershipTiers.Free, CreatedAtUtc = DateTimeOffset.UtcNow, UpdatedAtUtc = DateTimeOffset.UtcNow });
            await db.SaveChangesAsync();
            freeMb = (await db.Plans.AsNoTracking().SingleAsync(p => p.Code == PlanCodes.Free)).MaxScrollbackMegabytes;
        });
        using var client = _factory.CreateAuthenticatedClient(username);
        var profile = await client.GetFromJsonAsync<ProfileDto>("/api/me/profile");
        profile!.ScrollbackMaxAllowedBytes.Should().Be(freeMb * 1024L * 1024L);
    }

    [Fact]
    public async Task Profile_ProUser_ScrollbackMaxAllowedBytesMatchesProTier()
    {
        var username = $"u-{Guid.NewGuid():N}".Substring(0, 12);
        int proMb = 0;
        await _factory.SeedAsync(async db =>
        {
            var pro = await db.Plans.AsNoTracking().SingleAsync(p => p.Code == PlanCodes.ProYear);
            proMb = pro.MaxScrollbackMegabytes;
            db.Users.Add(new User { Id = Guid.NewGuid().ToString("N"), Username = username, Role = "user", Status = "active", MembershipTier = MembershipTiers.Pro, MembershipPlanId = pro.Id, MembershipExpiresAtUtc = DateTimeOffset.UtcNow.AddDays(30), CreatedAtUtc = DateTimeOffset.UtcNow, UpdatedAtUtc = DateTimeOffset.UtcNow });
            await db.SaveChangesAsync();
        });
        using var client = _factory.CreateAuthenticatedClient(username);
        var profile = await client.GetFromJsonAsync<ProfileDto>("/api/me/profile");
        profile!.ScrollbackMaxAllowedBytes.Should().Be(proMb * 1024L * 1024L);
    }

    public sealed record ProfileDto(long ScrollbackMaxAllowedBytes);
}
