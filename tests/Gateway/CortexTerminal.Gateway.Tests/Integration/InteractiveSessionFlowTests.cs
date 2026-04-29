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
        var workerRegistry = new InMemoryWorkerRegistry();
        workerRegistry.Register("worker-integration-1", "conn-integration-1");
        var sessions = new InMemorySessionCoordinator(workerRegistry);
        var sessionLaunchCoordinator = new SessionLaunchCoordinator(
            sessions,
            new ThrowingWorkerCommandDispatcher("dispatch failed"));

        var payload = await sessionLaunchCoordinator.CreateSessionAsync(
            "test-user",
            new CreateSessionRequest("shell", 120, 40),
            clientConnectionId: null,
            CancellationToken.None);

        payload.Should().Be(CreateSessionResult.Failure("worker-start-dispatch-failed"));

        var persistedSessions = GetSessions(sessions);
        persistedSessions.Values.Should().ContainSingle();
        var session = persistedSessions.Values.Single();
        session.AttachmentState.Should().Be(SessionAttachmentState.Exited);
        session.ExitReason.Should().Be("worker-start-dispatch-failed");
    }

    [Fact]
    public async Task CreateSession_WithSameClientRequestId_ReturnsSameSessionOnlyOnce()
    {
        var workerRegistry = new InMemoryWorkerRegistry();
        workerRegistry.Register("worker-integration-1", "conn-integration-1");
        using var baseFactory = new GatewayApplicationFactory();
        using var factory = baseFactory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                services.AddSingleton<IWorkerRegistry>(workerRegistry);
                services.AddSingleton<ISessionCoordinator>(new InMemorySessionCoordinator(workerRegistry));
                services.AddSingleton<IWorkerCommandDispatcher, RecordingWorkerCommandDispatcher>();
                services.AddSingleton<ISessionLaunchCoordinator>(serviceProvider =>
                    new SessionLaunchCoordinator(
                        serviceProvider.GetRequiredService<ISessionCoordinator>(),
                        serviceProvider.GetRequiredService<IWorkerCommandDispatcher>()));
            });
        });

        using var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", CreateAccessToken());
        var request = new CreateSessionRequest("shell", 120, 40, "boot-1");

        using var firstResponse = await client.PostAsJsonAsync("/api/sessions", request);
        using var secondResponse = await client.PostAsJsonAsync("/api/sessions", request);

        firstResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        secondResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var firstPayload = await firstResponse.Content.ReadFromJsonAsync<CreateSessionResponse>();
        var secondPayload = await secondResponse.Content.ReadFromJsonAsync<CreateSessionResponse>();

        firstPayload.Should().NotBeNull();
        secondPayload.Should().NotBeNull();
        secondPayload!.SessionId.Should().Be(firstPayload!.SessionId);

        var sessions = GetSessions(factory.Services.GetRequiredService<ISessionCoordinator>());
        sessions.Values.Should().ContainSingle();

        var dispatcher = factory.Services.GetRequiredService<IWorkerCommandDispatcher>();
        dispatcher.Should().BeOfType<RecordingWorkerCommandDispatcher>();
        ((RecordingWorkerCommandDispatcher)dispatcher).StartCommands.Should().ContainSingle();
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

    private sealed class RecordingWorkerCommandDispatcher : IWorkerCommandDispatcher
    {
        public List<CortexTerminal.Contracts.Streaming.StartSessionCommand> StartCommands { get; } = [];

        public Task StartSessionAsync(string workerConnectionId, CortexTerminal.Contracts.Streaming.StartSessionCommand command, CancellationToken cancellationToken)
        {
            StartCommands.Add(command);
            return Task.CompletedTask;
        }

        public Task WriteInputAsync(string workerConnectionId, CortexTerminal.Contracts.Streaming.WriteInputFrame frame, CancellationToken cancellationToken)
            => Task.CompletedTask;

        public Task ProbeLatencyAsync(string workerConnectionId, CortexTerminal.Contracts.Streaming.LatencyProbeFrame frame, CancellationToken cancellationToken)
            => Task.CompletedTask;

        public Task ResizeSessionAsync(string workerConnectionId, ResizePtyRequest request, CancellationToken cancellationToken)
            => Task.CompletedTask;

        public Task CloseSessionAsync(string workerConnectionId, CloseSessionRequest request, CancellationToken cancellationToken)
            => Task.CompletedTask;

        public Task UpgradeWorkerAsync(string workerConnectionId, CortexTerminal.Contracts.Streaming.UpgradeWorkerCommand command, CancellationToken cancellationToken)
            => Task.CompletedTask;
    }
}
