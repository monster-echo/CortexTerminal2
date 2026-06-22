using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using BCrypt.Net;
using CortexTerminal.Gateway.Data;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Auth;

public sealed class ProfileEndpointTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public ProfileEndpointTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    private static string Hash(string password) => BCrypt.Net.BCrypt.HashPassword(password);

    private async Task<string> SeedAuthenticatedUserAsync(string? identityPasswordHash, string? legacyPasswordHash)
    {
        var username = $"u-{Guid.NewGuid():N}".Substring(0, 12);
        await _factory.SeedAsync(async db =>
        {
            var user = new User
            {
                Id = Guid.NewGuid().ToString("N"),
                Username = username,
                Role = "user",
                Status = "active",
                CreatedAtUtc = DateTimeOffset.UtcNow,
                UpdatedAtUtc = DateTimeOffset.UtcNow,
                PasswordHash = legacyPasswordHash,
            };
            db.Users.Add(user);
            if (identityPasswordHash is not null)
            {
                db.UserIdentities.Add(new UserIdentity
                {
                    UserId = user.Id,
                    AuthProvider = "password",
                    AuthProviderId = user.Username,
                    PasswordHash = identityPasswordHash,
                    CreatedAtUtc = DateTimeOffset.UtcNow,
                });
            }
            await db.SaveChangesAsync();
        });
        return username;
    }

    private static async Task<bool> ReadHasPasswordAsync(HttpResponseMessage response)
    {
        var payload = await response.Content.ReadFromJsonAsync<JsonElement>();
        return payload.GetProperty("hasPassword").GetBoolean();
    }

    [Fact]
    public async Task HasPassword_True_WhenUserIdentityHasHash()
    {
        var username = await SeedAuthenticatedUserAsync(identityPasswordHash: Hash("any"), legacyPasswordHash: null);

        using var client = _factory.CreateAuthenticatedClient(username);
        using var response = await client.GetAsync("/api/me/profile");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        (await ReadHasPasswordAsync(response)).Should().BeTrue();
    }

    [Fact]
    public async Task HasPassword_True_WhenOnlyLegacyUsersHashExists()
    {
        var username = await SeedAuthenticatedUserAsync(identityPasswordHash: null, legacyPasswordHash: Hash("any"));

        using var client = _factory.CreateAuthenticatedClient(username);
        using var response = await client.GetAsync("/api/me/profile");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        (await ReadHasPasswordAsync(response)).Should().BeTrue();
    }

    [Fact]
    public async Task HasPassword_False_WhenUserHasNeitherIdentityNorLegacyHash()
    {
        var username = await SeedAuthenticatedUserAsync(identityPasswordHash: null, legacyPasswordHash: null);

        using var client = _factory.CreateAuthenticatedClient(username);
        using var response = await client.GetAsync("/api/me/profile");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        (await ReadHasPasswordAsync(response)).Should().BeFalse();
    }
}
