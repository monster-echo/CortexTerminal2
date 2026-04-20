using System.Net;
using System.Net.Http.Json;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Tests.Auth;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
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
}
