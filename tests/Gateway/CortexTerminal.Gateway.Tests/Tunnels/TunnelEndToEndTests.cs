using System.Net;
using System.Net.Http.Json;
using System.Text;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Tests.Auth;
using FluentAssertions;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Tunnels;

/// <summary>
/// Acceptance test for the full tunnel chain: visitor request -> Gateway TunnelMiddleware
/// -> SignalR TunnelHttpRequest invoke -> live worker hub handler -> response back to visitor.
/// Uses a real worker hub connection (not a mocked dispatcher) and the real REST create endpoint.
/// </summary>
public sealed class TunnelEndToEndTests
{
    [Fact]
    public async Task Visitor_request_flows_gateway_to_worker_and_back()
    {
        using var factory = new GatewayApplicationFactory();

        // Live worker hub connection: answers the port probe and serves tunneled HTTP requests
        // with a canned 200 + "PONG" so the response is observable end-to-end.
        await using var worker = factory.CreateAuthenticatedHubConnection("/hubs/worker");
        worker.On<TunnelHttpRequest, TunnelHttpResponse>("TunnelHttpRequest", _ =>
            new TunnelHttpResponse(200, new() { ["X-Proxied"] = new[] { "true" } }, Encoding.UTF8.GetBytes("PONG"), null));
        worker.On<int, ProbePortResponse>("ProbeTunnelPort", _ => new ProbePortResponse(true, null));
        await worker.StartAsync();
        await worker.InvokeAsync("RegisterWorker", "worker-e2e-tunnel");

        // Attached session bound to the registered worker (CreateSessionAsync picks it via
        // TryGetLeastBusyForUser, so WorkerConnectionId matches the live hub connection).
        var sessions = factory.Services.GetRequiredService<ISessionCoordinator>();
        var created = await sessions.CreateSessionAsync(
            "test-user",
            new CreateSessionRequest("shell", 120, 40),
            clientConnectionId: null,
            CancellationToken.None);
        created.IsSuccess.Should().BeTrue();
        var sessionId = created.Response!.SessionId;

        // Owner creates a tunnel for localhost:3000 through the real REST endpoint.
        using var client = factory.CreateAuthenticatedClient("test-user");
        TunnelDto dto;
        using (var create = await client.PostAsJsonAsync(
            $"/api/me/sessions/{sessionId}/tunnels",
            new CreateTunnelRequest(3000)))
        {
            create.StatusCode.Should().Be(HttpStatusCode.OK);
            dto = (await create.Content.ReadFromJsonAsync<TunnelDto>())!;
        }

        // Visitor (no JWT) hits the tunnel URL; gateway forwards to the worker, whose response
        // (status, headers, body) comes all the way back.
        using var visitor = factory.CreateClient();
        using var response = await visitor.GetAsync(new Uri(dto.Url).PathAndQuery);

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        response.Headers.Should().ContainKey("X-Proxied");
        response.Headers.GetValues("X-Proxied").Should().Equal("true");
        (await response.Content.ReadAsStringAsync()).Should().Be("PONG");
    }
}
