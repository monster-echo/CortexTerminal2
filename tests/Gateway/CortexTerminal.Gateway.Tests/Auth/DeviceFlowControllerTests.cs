using System.Net;
using System.Net.Http.Json;
using System.Net.Http.Headers;
using System.IdentityModel.Tokens.Jwt;
using System.Text;
using FluentAssertions;
using CortexTerminal.Contracts.Auth;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Data;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http.Connections;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.DependencyInjection;
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
        html.Should().Contain("<title>Corterm</title>");
    }
}

public sealed class GatewayApplicationFactory : WebApplicationFactory<Program>
{
    private string? _testWebRoot;

    protected override void ConfigureWebHost(Microsoft.AspNetCore.Hosting.IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");

        // Use in-memory database for hermetic tests
        builder.UseSetting("Database:UseInMemory", "true");

        // Create a temp wwwroot with a stub index.html so static file serving
        // tests work even when the real SPA build output is absent (e.g. in CI).
        _testWebRoot = Path.Combine(Path.GetTempPath(), $"corterm-test-wwwroot-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_testWebRoot);
        File.WriteAllText(
            Path.Combine(_testWebRoot, "index.html"),
            """<!doctype html><html><head><title>Corterm</title></head><body></body></html>""");
        builder.UseWebRoot(_testWebRoot);
    }

    protected override void Dispose(bool disposing)
    {
        if (_testWebRoot is not null && Directory.Exists(_testWebRoot))
        {
            try { Directory.Delete(_testWebRoot, recursive: true); } catch { }
        }
        base.Dispose(disposing);
    }

    public HttpClient CreateAuthenticatedClient()
        => CreateAuthenticatedClient("test-user");

    public HttpClient CreateAuthenticatedClient(string username, string? role = null)
    {
        var client = CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });

        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", CreateAccessToken(username, role));
        return client;
    }

    public HttpClient CreateAdminClient()
        => CreateAuthenticatedClient("test-admin", "admin");

    public HubConnection CreateHubConnection(string path)
        => CreateHubConnection(path, accessToken: null);

    /// <summary>
    /// Run a query against the in-memory AppDbContext. The host must already be running
    /// (i.e. CreateClient/CreateAuthenticatedClient has been called) so Services is populated.
    /// </summary>
    public async Task<T> QueryAsync<T>(Func<AppDbContext, Task<T>> action)
    {
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        return await action(db);
    }

    /// <summary>
    /// Seed the in-memory AppDbContext with custom data before a test runs.
    /// </summary>
    public async Task SeedAsync(Func<AppDbContext, Task> action)
    {
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await action(db);
    }

    public HubConnection CreateAuthenticatedHubConnection(string path)
        => CreateHubConnection(path, CreateAccessToken());

    public string CreateAccessToken()
        => CreateAccessToken("test-user");

    public string CreateAccessToken(string username, string? role = null)
    {
        var claims = new System.Collections.Generic.List<System.Security.Claims.Claim>
        {
            new System.Security.Claims.Claim(JwtRegisteredClaimNames.Sub, username),
            new System.Security.Claims.Claim("oi_tkn_typ", "access_token")
        };
        if (!string.IsNullOrEmpty(role))
            claims.Add(new System.Security.Claims.Claim("role", role));
        var signingKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes("gateway-auth-signing-key-minimum-32b"));
        var credentials = new SigningCredentials(signingKey, SecurityAlgorithms.HmacSha256);
        var token = new JwtSecurityToken(
            issuer: "https://gateway.local/",
            audience: "corterm-gateway",
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
