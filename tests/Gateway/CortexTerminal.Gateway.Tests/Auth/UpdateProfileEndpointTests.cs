using System.Net;
using System.Net.Http.Json;
using CortexTerminal.Gateway.Data;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Auth;

public sealed class UpdateProfileEndpointTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public UpdateProfileEndpointTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    private async Task<string> SeedAuthenticatedUserAsync()
    {
        var username = $"u-{Guid.NewGuid():N}".Substring(0, 12);
        await _factory.SeedAsync(async db =>
        {
            db.Users.Add(new User
            {
                Id = Guid.NewGuid().ToString("N"),
                Username = username,
                DisplayName = "Old Name",
                Role = "user",
                Status = "active",
                CreatedAtUtc = DateTimeOffset.UtcNow,
                UpdatedAtUtc = DateTimeOffset.UtcNow,
            });
            await db.SaveChangesAsync();
        });
        return username;
    }

    [Fact]
    public async Task UpdateProfile_ChangesDisplayName()
    {
        var username = await SeedAuthenticatedUserAsync();

        using var client = _factory.CreateAuthenticatedClient(username);
        using var response = await client.PostAsJsonAsync("/api/me/profile", new { DisplayName = "New Name" });

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var saved = await _factory.QueryAsync(db => db.Users.FirstAsync(u => u.Username == username));
        saved.DisplayName.Should().Be("New Name");
    }

    [Fact]
    public async Task UpdateProfile_TrimsDisplayName()
    {
        var username = await SeedAuthenticatedUserAsync();

        using var client = _factory.CreateAuthenticatedClient(username);
        using var response = await client.PostAsJsonAsync("/api/me/profile", new { DisplayName = "  Trimmed  " });

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var saved = await _factory.QueryAsync(db => db.Users.FirstAsync(u => u.Username == username));
        saved.DisplayName.Should().Be("Trimmed");
    }

    [Fact]
    public async Task UpdateProfile_RejectsEmptyDisplayName()
    {
        var username = await SeedAuthenticatedUserAsync();

        using var client = _factory.CreateAuthenticatedClient(username);
        using var response = await client.PostAsJsonAsync("/api/me/profile", new { DisplayName = "   " });

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task UpdateProfile_RejectsDisplayNameOver32Chars()
    {
        var username = await SeedAuthenticatedUserAsync();

        using var client = _factory.CreateAuthenticatedClient(username);
        using var response = await client.PostAsJsonAsync("/api/me/profile", new { DisplayName = new string('x', 33) });

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task UpdateProfile_DoesNotInvalidateToken()
    {
        // Changing DisplayName must not invalidate the JWT (whose subject is username).
        var username = await SeedAuthenticatedUserAsync();

        using var client = _factory.CreateAuthenticatedClient(username);
        using var update = await client.PostAsJsonAsync("/api/me/profile", new { DisplayName = "New Name" });
        update.StatusCode.Should().Be(HttpStatusCode.OK);

        // Same token still works afterwards.
        using var profile = await client.GetAsync("/api/me/profile");
        profile.StatusCode.Should().Be(HttpStatusCode.OK);
    }
}
