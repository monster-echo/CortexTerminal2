using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.IdentityModel.Tokens.Jwt;
using System.Text;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Tests.Auth;
using CortexTerminal.Gateway.Tests.Hubs;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using System.Reflection;
using Microsoft.IdentityModel.Tokens;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Integration;

public sealed class InteractiveSessionFlowTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public InteractiveSessionFlowTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task CreateSession_WithRegisteredWorker_ReturnsSessionStarted()
    {
        // Pre-register a worker so session creation succeeds
        var registry = _factory.Services.GetRequiredService<IWorkerRegistry>();
        registry.Register("worker-integration-1", "conn-integration-1");

        using var client = _factory.CreateAuthenticatedClient();

        using var response = await client.PostAsJsonAsync("/api/sessions", new CreateSessionRequest("shell", 120, 40));

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var payload = await response.Content.ReadFromJsonAsync<CreateSessionResponse>();
        payload.Should().NotBeNull();
        payload!.SessionId.Should().StartWith("sess_");
        payload.WorkerId.Should().Be("worker-integration-1");
    }

    [Fact]
    public async Task CreateSession_WithNonShellRuntime_ReturnsBadRequest()
    {
        using var client = _factory.CreateAuthenticatedClient();

        using var response = await client.PostAsJsonAsync("/api/sessions", new CreateSessionRequest("docker", 120, 40));

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task CreateSession_WithNoWorkers_Returns503()
    {
        // Use a fresh factory to ensure no pre-registered workers
        using var freshFactory = new GatewayApplicationFactory();
        using var client = freshFactory.CreateAuthenticatedClient();

        using var response = await client.PostAsJsonAsync("/api/sessions", new CreateSessionRequest("shell", 120, 40));

        response.StatusCode.Should().Be(HttpStatusCode.ServiceUnavailable);
    }

    [Fact]
    public async Task CreateSession_WhenStartSessionDispatchFails_ReturnsUnavailableAndExitsSession()
    {
        using var factory = _factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                services.AddSingleton<IWorkerCommandDispatcher>(new ThrowingWorkerCommandDispatcher("dispatch failed"));
            });
        });

        var registry = factory.Services.GetRequiredService<IWorkerRegistry>();
        registry.Register("worker-integration-1", "conn-integration-1");

        using var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", CreateAccessToken());

        using var response = await client.PostAsJsonAsync("/api/sessions", new CreateSessionRequest("shell", 120, 40));

        response.StatusCode.Should().Be(HttpStatusCode.ServiceUnavailable);
        var payload = await response.Content.ReadFromJsonAsync<CreateSessionResult>();
        payload.Should().Be(CreateSessionResult.Failure("worker-start-dispatch-failed"));

        var sessions = GetSessions(factory.Services.GetRequiredService<ISessionCoordinator>());
        sessions.Values.Should().ContainSingle();
        var session = sessions.Values.Single();
        session.AttachmentState.Should().Be(SessionAttachmentState.Exited);
        session.ExitReason.Should().Be("worker-start-dispatch-failed");
    }

    private static System.Collections.Concurrent.ConcurrentDictionary<string, SessionRecord> GetSessions(ISessionCoordinator coordinator)
        => (System.Collections.Concurrent.ConcurrentDictionary<string, SessionRecord>)coordinator.GetType()
            .GetField("_sessions", BindingFlags.Instance | BindingFlags.NonPublic)!
            .GetValue(coordinator)!;

    private static string CreateAccessToken()
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
}
