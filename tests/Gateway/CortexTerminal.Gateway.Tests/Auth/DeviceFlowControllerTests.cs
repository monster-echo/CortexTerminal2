using System.Net;
using System.Net.Http.Json;
using System.Net.Http.Headers;
using System.IdentityModel.Tokens.Jwt;
using System.Text;
using FluentAssertions;
using CortexTerminal.Contracts.Auth;
using CortexTerminal.Contracts.Sessions;
using Microsoft.AspNetCore.Http.Connections;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.IdentityModel.Tokens;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Auth;

public sealed class DeviceFlowControllerTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public DeviceFlowControllerTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task StartDeviceFlow_ReturnsStartContract()
    {
        using var client = _factory.CreateClient();

        using var response = await client.PostAsync("/api/auth/device-flow", content: null);

        response.StatusCode.Should().Be(HttpStatusCode.OK);

        var payload = await response.Content.ReadFromJsonAsync<DeviceFlowStartResponse>();
        payload.Should().NotBeNull();
        payload!.DeviceCode.Should().NotBeNullOrWhiteSpace();
        payload.UserCode.Should().NotBeNullOrWhiteSpace();
        payload.VerificationUri.Should().NotBeNullOrWhiteSpace();
        payload.ExpiresInSeconds.Should().BePositive();
        payload.PollIntervalSeconds.Should().BePositive();
    }

    [Fact]
    public async Task CreateSession_RejectsAnonymousRequests()
    {
        using var client = _factory.CreateClient();

        using var response = await client.PostAsJsonAsync("/api/sessions", new CreateSessionRequest("shell", 120, 40));

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task CreateSession_AllowsAuthenticatedRequests_ButReturnsUnavailableUntilWorkersExist()
    {
        using var client = _factory.CreateAuthenticatedClient();

        using var response = await client.PostAsJsonAsync("/api/sessions", new CreateSessionRequest("shell", 120, 40));

        response.StatusCode.Should().Be(HttpStatusCode.ServiceUnavailable);

        var payload = await response.Content.ReadFromJsonAsync<CreateSessionResult>();
        payload.Should().Be(CreateSessionResult.Failure("no-worker-available"));
    }

    [Fact]
    public async Task RootPath_ServesGatewayConsoleShell()
    {
        using var client = _factory.CreateClient();

        using var response = await client.GetAsync("/");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        response.Content.Headers.ContentType?.MediaType.Should().Be("text/html");
        var html = await response.Content.ReadAsStringAsync();
        html.Should().Contain("<title>Gateway Console</title>");
    }
}

public sealed class GatewayApplicationFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(Microsoft.AspNetCore.Hosting.IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
    }

    public HttpClient CreateAuthenticatedClient()
    {
        var client = CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });

        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", CreateAccessToken());
        return client;
    }

    public HubConnection CreateHubConnection(string path)
        => CreateHubConnection(path, accessToken: null);

    public HubConnection CreateAuthenticatedHubConnection(string path)
        => CreateHubConnection(path, CreateAccessToken());

    public string CreateAccessToken()
    {
        var claims = new[]
        {
            new System.Security.Claims.Claim(JwtRegisteredClaimNames.Sub, "test-user"),
            new System.Security.Claims.Claim("oi_tkn_typ", "access_token")
        };
        var signingKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes("gateway-auth-signing-key-minimum-32b"));
        var credentials = new SigningCredentials(signingKey, SecurityAlgorithms.HmacSha256);
        var token = new JwtSecurityToken(
            issuer: "https://gateway.local/",
            audience: "cortex-terminal-gateway",
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(5),
            signingCredentials: credentials);
        token.Header["typ"] = "at+jwt";

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private HubConnection CreateHubConnection(string path, string? accessToken)
        => new HubConnectionBuilder()
            .WithUrl($"http://localhost{path}", options =>
            {
                options.HttpMessageHandlerFactory = _ => Server.CreateHandler();
                options.Transports = HttpTransportType.LongPolling;
                if (accessToken is not null)
                {
                    options.AccessTokenProvider = () => Task.FromResult<string?>(accessToken);
                }
            })
            .Build();
}
