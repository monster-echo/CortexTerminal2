using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using BCrypt.Net;
using CortexTerminal.Gateway.Data;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Auth;

public sealed class PasswordLoginEndpointTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public PasswordLoginEndpointTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    private static string Hash(string password) => BCrypt.Net.BCrypt.HashPassword(password);

    private async Task<string> LoginAsync(HttpClient client, string username, string password)
    {
        using var response = await client.PostAsJsonAsync(
            "/api/auth/password/login",
            new { Username = username, Password = password });
        var body = await response.Content.ReadAsStringAsync();
        return $"{{ status = {(int)response.StatusCode}, body = {body} }}";
    }

    private async Task<(HttpStatusCode status, string? accessToken)> LoginAndGetAsync(HttpClient client, string username, string password)
    {
        using var response = await client.PostAsJsonAsync(
            "/api/auth/password/login",
            new { Username = username, Password = password });
        if (!response.IsSuccessStatusCode)
            return (response.StatusCode, null);
        var payload = await response.Content.ReadFromJsonAsync<JsonElement>();
        return (response.StatusCode, payload.GetProperty("accessToken").GetString());
    }

    [Fact]
    public async Task SeededLegacyUser_CanLogin_ViaUsersPasswordHashFallback()
    {
        // The factory seeds `test/test123` into Users.PasswordHash with no UserIdentity.
        using var client = _factory.CreateClient();

        var (status, token) = await LoginAndGetAsync(client, "test", "test123");

        status.Should().Be(HttpStatusCode.OK);
        token.Should().NotBeNullOrWhiteSpace();
    }

    [Fact]
    public async Task LoginByUserIdentity_Username_Succeeds()
    {
        const string username = "alice";
        const string password = "alice-secret";
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
            };
            db.Users.Add(user);
            db.UserIdentities.Add(new UserIdentity
            {
                UserId = user.Id,
                AuthProvider = "password",
                AuthProviderId = username,
                Email = "alice@example.com",
                PhoneNormalized = "13800138000",
                PasswordHash = Hash(password),
                CreatedAtUtc = DateTimeOffset.UtcNow,
            });
            await db.SaveChangesAsync();
        });
        using var client = _factory.CreateClient();

        var (status, token) = await LoginAndGetAsync(client, username, password);

        status.Should().Be(HttpStatusCode.OK);
        token.Should().NotBeNullOrWhiteSpace();
    }

    [Fact]
    public async Task LoginByUserIdentity_Email_Succeeds()
    {
        const string password = "alice-secret";
        await _factory.SeedAsync(async db =>
        {
            var user = new User
            {
                Id = Guid.NewGuid().ToString("N"),
                Username = "alice",
                Role = "user",
                Status = "active",
                CreatedAtUtc = DateTimeOffset.UtcNow,
                UpdatedAtUtc = DateTimeOffset.UtcNow,
            };
            db.Users.Add(user);
            db.UserIdentities.Add(new UserIdentity
            {
                UserId = user.Id,
                AuthProvider = "password",
                AuthProviderId = "alice",
                Email = "alice@example.com",
                PhoneNormalized = "13800138000",
                PasswordHash = Hash(password),
                CreatedAtUtc = DateTimeOffset.UtcNow,
            });
            await db.SaveChangesAsync();
        });
        using var client = _factory.CreateClient();

        var (status, token) = await LoginAndGetAsync(client, "alice@example.com", password);

        status.Should().Be(HttpStatusCode.OK);
        token.Should().NotBeNullOrWhiteSpace();
    }

    [Fact]
    public async Task LoginByUserIdentity_PhoneNormalized_Succeeds()
    {
        const string password = "alice-secret";
        await _factory.SeedAsync(async db =>
        {
            var user = new User
            {
                Id = Guid.NewGuid().ToString("N"),
                Username = "alice",
                Role = "user",
                Status = "active",
                CreatedAtUtc = DateTimeOffset.UtcNow,
                UpdatedAtUtc = DateTimeOffset.UtcNow,
            };
            db.Users.Add(user);
            db.UserIdentities.Add(new UserIdentity
            {
                UserId = user.Id,
                AuthProvider = "password",
                AuthProviderId = "alice",
                Email = "alice@example.com",
                PhoneNormalized = "13800138000",
                PasswordHash = Hash(password),
                CreatedAtUtc = DateTimeOffset.UtcNow,
            });
            await db.SaveChangesAsync();
        });
        using var client = _factory.CreateClient();

        // NormalizePhone keeps the last 11 digits, so `+8613800138000` and `13800138000` should both match.
        var (status, token) = await LoginAndGetAsync(client, "+8613800138000", password);

        status.Should().Be(HttpStatusCode.OK);
        token.Should().NotBeNullOrWhiteSpace();
    }

    [Fact]
    public async Task WrongPassword_Returns401_DoesNotLeakAccountExistence()
    {
        const string password = "alice-secret";
        await _factory.SeedAsync(async db =>
        {
            var user = new User
            {
                Id = Guid.NewGuid().ToString("N"),
                Username = "alice",
                Role = "user",
                Status = "active",
                CreatedAtUtc = DateTimeOffset.UtcNow,
                UpdatedAtUtc = DateTimeOffset.UtcNow,
            };
            db.Users.Add(user);
            db.UserIdentities.Add(new UserIdentity
            {
                UserId = user.Id,
                AuthProvider = "password",
                AuthProviderId = "alice",
                PasswordHash = Hash(password),
                CreatedAtUtc = DateTimeOffset.UtcNow,
            });
            await db.SaveChangesAsync();
        });
        using var client = _factory.CreateClient();

        // Existing user, wrong password
        var (existingStatus, _) = await LoginAndGetAsync(client, "alice", "wrong-password");
        // Non-existent user, same wrong password
        var (ghostStatus, _) = await LoginAndGetAsync(client, "ghost", "wrong-password");

        existingStatus.Should().Be(HttpStatusCode.Unauthorized);
        ghostStatus.Should().Be(HttpStatusCode.Unauthorized,
            "login should not differentiate between 'user not found' and 'wrong password'");
    }
}
