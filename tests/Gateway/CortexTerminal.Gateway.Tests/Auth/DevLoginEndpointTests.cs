using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using CortexTerminal.Contracts.Auth;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Auth;

public sealed class DevLoginEndpointTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public DevLoginEndpointTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task DevLogin_ReturnsBearerTokenForUsername()
    {
        using var client = _factory.CreateClient();

        using var response = await client.PostAsJsonAsync("/api/dev/login", new DevLoginRequest("alice", "password"));

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var payload = await response.Content.ReadFromJsonAsync<DevLoginResponse>();
        payload.Should().NotBeNull();
        payload!.AccessToken.Should().NotBeNullOrWhiteSpace();

        var token = new JwtSecurityTokenHandler().ReadJwtToken(payload.AccessToken);
        token.Claims.Should().ContainSingle(claim => claim.Type == JwtRegisteredClaimNames.Sub && claim.Value == "alice");
    }
}
