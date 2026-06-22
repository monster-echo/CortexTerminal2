using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using CortexTerminal.Gateway.Tests.Auth;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Stats;

public sealed class MyStatsEndpointTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public MyStatsEndpointTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Anonymous_Returns401()
    {
        using var client = _factory.CreateClient();

        using var response = await client.GetAsync("/api/me/stats");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Authenticated_NoSessions_ReturnsZeros()
    {
        using var client = _factory.CreateAuthenticatedClient("empty-user");

        using var response = await client.GetAsync("/api/me/stats");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var payload = await response.Content.ReadFromJsonAsync<JsonElement>();

        payload.GetProperty("totalSessions").GetInt32().Should().Be(0);
        payload.GetProperty("activeSessions").GetInt32().Should().Be(0);
        payload.GetProperty("detachedSessions").GetInt32().Should().Be(0);
        payload.GetProperty("exitedSessions").GetInt32().Should().Be(0);
        payload.GetProperty("totalWorkers").GetInt32().Should().Be(0);
        payload.GetProperty("onlineWorkers").GetInt32().Should().Be(0);
        payload.GetProperty("bytesTransferred").GetInt32().Should().Be(0);
        payload.GetProperty("mostRecentSessionAtUtc").ValueKind.Should().Be(JsonValueKind.Null);
    }

    [Fact]
    public async Task Authenticated_ReturnsExpectedShape()
    {
        using var client = _factory.CreateAuthenticatedClient("shape-check");

        using var response = await client.GetAsync("/api/me/stats");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var payload = await response.Content.ReadFromJsonAsync<JsonElement>();

        // All expected fields present
        payload.TryGetProperty("totalSessions", out _).Should().BeTrue();
        payload.TryGetProperty("activeSessions", out _).Should().BeTrue();
        payload.TryGetProperty("detachedSessions", out _).Should().BeTrue();
        payload.TryGetProperty("exitedSessions", out _).Should().BeTrue();
        payload.TryGetProperty("totalWorkers", out _).Should().BeTrue();
        payload.TryGetProperty("onlineWorkers", out _).Should().BeTrue();
        payload.TryGetProperty("bytesTransferred", out _).Should().BeTrue();
        payload.TryGetProperty("mostRecentSessionAtUtc", out _).Should().BeTrue();
    }
}
