using System.Net;
using System.Net.Http.Json;
using BCrypt.Net;
using CortexTerminal.Gateway.Data;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Auth;

public sealed class EnsureLastLoginAtUtcTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public EnsureLastLoginAtUtcTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    private static string Hash(string password) => BCrypt.Net.BCrypt.HashPassword(password);

    [Fact]
    public async Task PasswordLogin_Success_SetsLastLoginAtUtc()
    {
        const string username = "lastlogin-test";
        const string password = "secret";
        var beforeLogin = DateTimeOffset.UtcNow.AddMinutes(-1);
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
                PasswordHash = Hash(password),
                CreatedAtUtc = DateTimeOffset.UtcNow,
            });
            await db.SaveChangesAsync();
        });

        using var client = _factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/auth/password/login",
            new { Username = username, Password = password });

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var lastLogin = await _factory.QueryAsync(async db =>
        {
            var user = await db.Users.FirstAsync(u => u.Username == username);
            return user.LastLoginAtUtc;
        });

        lastLogin.Should().NotBeNull();
        lastLogin!.Value.Should().BeAfter(beforeLogin);
    }

    [Fact]
    public async Task PasswordLogin_Failure_DoesNotSetLastLoginAtUtc()
    {
        const string username = "no-login";
        const string password = "secret";
        await _factory.SeedAsync(async db =>
        {
            var user = new User
            {
                Id = Guid.NewGuid().ToString("N"),
                Username = username,
                Role = "user",
                Status = "active",
                LastLoginAtUtc = null,
                CreatedAtUtc = DateTimeOffset.UtcNow,
                UpdatedAtUtc = DateTimeOffset.UtcNow,
            };
            db.Users.Add(user);
            db.UserIdentities.Add(new UserIdentity
            {
                UserId = user.Id,
                AuthProvider = "password",
                AuthProviderId = username,
                PasswordHash = Hash(password),
                CreatedAtUtc = DateTimeOffset.UtcNow,
            });
            await db.SaveChangesAsync();
        });

        using var client = _factory.CreateClient();
        using var response = await client.PostAsJsonAsync(
            "/api/auth/password/login",
            new { Username = username, Password = "wrong-password" });

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        var lastLogin = await _factory.QueryAsync(async db =>
        {
            var user = await db.Users.FirstAsync(u => u.Username == username);
            return user.LastLoginAtUtc;
        });

        lastLogin.Should().BeNull("failed login should not update LastLoginAtUtc");
    }
}
