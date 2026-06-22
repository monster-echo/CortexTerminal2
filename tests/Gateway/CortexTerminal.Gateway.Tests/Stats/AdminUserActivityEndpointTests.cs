using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Tests.Auth;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Stats;

public sealed class AdminUserActivityEndpointTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public AdminUserActivityEndpointTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    private async Task SeedAdminUserAsync()
    {
        await _factory.SeedAsync(async db =>
        {
            if (!await db.Users.AnyAsync(u => u.Username == "test-admin"))
            {
                db.Users.Add(new User
                {
                    Id = Guid.NewGuid().ToString("N"),
                    Username = "test-admin",
                    Role = "admin",
                    Status = "active",
                    CreatedAtUtc = DateTimeOffset.UtcNow,
                    UpdatedAtUtc = DateTimeOffset.UtcNow,
                });
                await db.SaveChangesAsync();
            }
        });
    }

    [Fact]
    public async Task NonAdmin_Returns403()
    {
        using var client = _factory.CreateAuthenticatedClient("regular-user", role: null);

        using var response = await client.GetAsync("/api/admin/user-activity");

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Admin_NoUsers_ReturnsOnlyAdmin()
    {
        await SeedAdminUserAsync();
        using var client = _factory.CreateAdminClient();

        using var response = await client.GetAsync("/api/admin/user-activity");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var payload = await response.Content.ReadFromJsonAsync<JsonElement>();

        payload.GetProperty("onlineUserCount").GetInt32().Should().Be(0);
        payload.GetProperty("activeSessionCount").GetInt32().Should().Be(0);
        // test-admin + pre-seeded dev "test" user
        payload.GetProperty("users").GetArrayLength().Should().BeGreaterThanOrEqualTo(1);
    }

    [Fact]
    public async Task Admin_WithSeededUsers_ReturnsUsersInPayload()
    {
        await SeedAdminUserAsync();
        await _factory.SeedAsync(async db =>
        {
            db.Users.Add(new User
            {
                Id = Guid.NewGuid().ToString("N"),
                Username = "alice",
                Role = "user",
                Status = "active",
                LastLoginAtUtc = DateTimeOffset.UtcNow.AddHours(-2),
                CreatedAtUtc = DateTimeOffset.UtcNow.AddDays(-10),
                UpdatedAtUtc = DateTimeOffset.UtcNow,
            });
            db.Users.Add(new User
            {
                Id = Guid.NewGuid().ToString("N"),
                Username = "bob",
                Role = "user",
                Status = "active",
                LastLoginAtUtc = DateTimeOffset.UtcNow.AddMinutes(-30),
                CreatedAtUtc = DateTimeOffset.UtcNow.AddDays(-5),
                UpdatedAtUtc = DateTimeOffset.UtcNow,
            });
            await db.SaveChangesAsync();
        });

        using var client = _factory.CreateAdminClient();

        using var response = await client.GetAsync("/api/admin/user-activity");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var payload = await response.Content.ReadFromJsonAsync<JsonElement>();

        var users = payload.GetProperty("users");
        users.GetArrayLength().Should().BeGreaterThanOrEqualTo(3); // alice, bob, test-admin + pre-seeded

        var usernames = users.EnumerateArray()
            .Select(u => u.GetProperty("username").GetString())
            .ToArray();
        usernames.Should().Contain(new[] { "alice", "bob", "test-admin" });

        // Check shape per user
        var alice = users.EnumerateArray().First(u => u.GetProperty("username").GetString() == "alice");
        alice.GetProperty("isOnline").GetBoolean().Should().BeFalse();
        alice.GetProperty("activeSessionCount").GetInt32().Should().Be(0);
        alice.GetProperty("lastLoginAtUtc").ValueKind.Should().NotBe(JsonValueKind.Null);
    }

    [Fact]
    public async Task Admin_ReturnsExpectedTopLevelShape()
    {
        await SeedAdminUserAsync();
        using var client = _factory.CreateAdminClient();

        using var response = await client.GetAsync("/api/admin/user-activity");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var payload = await response.Content.ReadFromJsonAsync<JsonElement>();

        payload.TryGetProperty("onlineUserCount", out _).Should().BeTrue();
        payload.TryGetProperty("activeSessionCount", out _).Should().BeTrue();
        payload.TryGetProperty("users", out _).Should().BeTrue();
        payload.TryGetProperty("sessions", out _).Should().BeTrue();
    }
}
