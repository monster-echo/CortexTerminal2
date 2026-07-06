using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using CortexTerminal.Gateway.Data;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Auth;

public sealed class AvatarEndpointTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public AvatarEndpointTests(GatewayApplicationFactory factory)
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
                Role = "user",
                Status = "active",
                CreatedAtUtc = DateTimeOffset.UtcNow,
                UpdatedAtUtc = DateTimeOffset.UtcNow,
            });
            await db.SaveChangesAsync();
        });
        return username;
    }

    private const string TinyPngBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC";

    [Fact]
    public async Task UploadAvatar_StoresBytesAndExposesAvatarUrl()
    {
        var username = await SeedAuthenticatedUserAsync();

        using var client = _factory.CreateAuthenticatedClient(username);
        using var response = await client.PostAsync(
            "/api/me/avatar", new StringContent($"data:image/png;base64,{TinyPngBase64}"));

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var payload = await response.Content.ReadFromJsonAsync<JsonElement>();
        payload.GetProperty("success").GetBoolean().Should().BeTrue();
        payload.GetProperty("avatarUrl").GetString().Should().Contain("/api/users/");

        var saved = await _factory.QueryAsync(db => db.Users.FirstAsync(u => u.Username == username));
        saved.AvatarData.Should().NotBeNull();
        saved.AvatarContentType.Should().Be("image/png");
        saved.AvatarUrl.Should().Contain("/api/users/");
    }

    [Fact]
    public async Task UploadAvatar_AcceptsRawBase64WithoutDataPrefix()
    {
        var username = await SeedAuthenticatedUserAsync();

        using var client = _factory.CreateAuthenticatedClient(username);
        using var response = await client.PostAsync("/api/me/avatar", new StringContent(TinyPngBase64));

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var saved = await _factory.QueryAsync(db => db.Users.FirstAsync(u => u.Username == username));
        saved.AvatarContentType.Should().Be("image/png");
    }

    [Fact]
    public async Task UploadAvatar_RejectsOver2MB()
    {
        var username = await SeedAuthenticatedUserAsync();
        var raw = new byte[(2 * 1024 * 1024) + 1024];
        var base64 = Convert.ToBase64String(raw);

        using var client = _factory.CreateAuthenticatedClient(username);
        using var response = await client.PostAsync("/api/me/avatar", new StringContent(base64));

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task UploadAvatar_RejectsEmptyBody()
    {
        var username = await SeedAuthenticatedUserAsync();

        using var client = _factory.CreateAuthenticatedClient(username);
        using var response = await client.PostAsync("/api/me/avatar", new StringContent(""));

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }
}
