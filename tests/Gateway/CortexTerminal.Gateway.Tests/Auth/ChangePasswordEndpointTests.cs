using System.Net;
using System.Net.Http.Json;
using BCrypt.Net;
using CortexTerminal.Gateway.Data;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Auth;

public sealed class ChangePasswordEndpointTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public ChangePasswordEndpointTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    private static string Hash(string password) => BCrypt.Net.BCrypt.HashPassword(password);

    /// <summary>
    /// CreateAuthenticatedClient mints a token whose subject is the username, so each test
    /// uses a unique username to avoid state collisions in the shared in-memory DB.
    /// </summary>
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

    [Fact]
    public async Task ChangePassword_OnUserIdentityUser_UpdatesIdentityHash_AndKeepsLegacyUntouched()
    {
        var username = await SeedAuthenticatedUserAsync(identityPasswordHash: Hash("old-pw"), legacyPasswordHash: null);

        using var client = _factory.CreateAuthenticatedClient(username);
        using var response = await client.PutAsJsonAsync(
            "/api/me/password",
            new { CurrentPassword = "old-pw", NewPassword = "new-pw-12345" });

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var identity = await _factory.QueryAsync(db =>
            db.UserIdentities.FirstAsync(i => i.AuthProvider == "password" && i.AuthProviderId == username));
        BCrypt.Net.BCrypt.Verify("new-pw-12345", identity.PasswordHash).Should().BeTrue();

        var user = await _factory.QueryAsync(db => db.Users.FirstAsync(u => u.Username == username));
        user.PasswordHash.Should().BeNull("legacy column is no longer the source of truth");
    }

    [Fact]
    public async Task ChangePassword_OnLegacyUser_ReadsCurrentFromUsersPasswordHash()
    {
        var username = await SeedAuthenticatedUserAsync(identityPasswordHash: null, legacyPasswordHash: Hash("old-pw"));

        using var client = _factory.CreateAuthenticatedClient(username);
        using var response = await client.PutAsJsonAsync(
            "/api/me/password",
            new { CurrentPassword = "old-pw", NewPassword = "new-pw-12345" });

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var identityCount = await _factory.QueryAsync(db =>
            db.UserIdentities.CountAsync(i => i.AuthProvider == "password" && i.AuthProviderId == username));
        identityCount.Should().Be(1, "legacy user should get a password identity created on first change");

        var identity = await _factory.QueryAsync(db =>
            db.UserIdentities.FirstAsync(i => i.AuthProvider == "password" && i.AuthProviderId == username));
        BCrypt.Net.BCrypt.Verify("new-pw-12345", identity.PasswordHash).Should().BeTrue();
    }

    [Fact]
    public async Task ChangePassword_OnOAuthOnlyUser_CreatesIdentityWithoutCurrentPassword()
    {
        // Huawei/Apple/Phone-only user has neither a password identity nor a legacy hash.
        var username = await SeedAuthenticatedUserAsync(identityPasswordHash: null, legacyPasswordHash: null);

        using var client = _factory.CreateAuthenticatedClient(username);
        using var response = await client.PutAsJsonAsync(
            "/api/me/password",
            new { NewPassword = "first-pw-12345" });

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var identity = await _factory.QueryAsync(db =>
            db.UserIdentities.FirstAsync(i => i.AuthProvider == "password" && i.AuthProviderId == username));
        BCrypt.Net.BCrypt.Verify("first-pw-12345", identity.PasswordHash).Should().BeTrue();
    }

    [Fact]
    public async Task ChangePassword_WrongCurrentPassword_Returns400()
    {
        var username = await SeedAuthenticatedUserAsync(identityPasswordHash: Hash("old-pw"), legacyPasswordHash: null);

        using var client = _factory.CreateAuthenticatedClient(username);
        using var response = await client.PutAsJsonAsync(
            "/api/me/password",
            new { CurrentPassword = "wrong-pw", NewPassword = "new-pw-12345" });

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var body = await response.Content.ReadFromJsonAsync<Dictionary<string, string>>();
        body!["error"].Should().Contain("Current password is incorrect");
    }
}
