using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using CortexTerminal.Contracts.Console;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using CortexTerminal.Gateway.Tests.Auth;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Console;

public sealed class ConsoleQueryEndpointTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public ConsoleQueryEndpointTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task MeEndpoints_ReturnOnlyCurrentUsersSessionsAndWorkers()
    {
        var workers = _factory.Services.GetRequiredService<IWorkerRegistry>();
        workers.Register("worker-alice", "conn-alice", ownerUserId: "alice");
        workers.Register("worker-bob", "conn-bob", ownerUserId: "bob");

        var sessions = _factory.Services.GetRequiredService<ISessionCoordinator>();
        var aliceSession = await sessions.CreateSessionAsync("alice", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var bobSession = await sessions.CreateSessionAsync("bob", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);

        using var aliceClient = _factory.CreateClient();
        aliceClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", await GetAccessTokenAsync("alice"));

        using var sessionsResponse = await aliceClient.GetAsync("/api/me/sessions");
        sessionsResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        var aliceSessions = await sessionsResponse.Content.ReadFromJsonAsync<SessionSummaryDto[]>();
        aliceSessions.Should().NotBeNull();
        aliceSessions!.Should().ContainSingle(session => session.SessionId == aliceSession.Response!.SessionId);

        using var workersResponse = await aliceClient.GetAsync("/api/me/workers");
        workersResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        var aliceWorkers = await workersResponse.Content.ReadFromJsonAsync<WorkerSummaryDto[]>();
        aliceWorkers.Should().NotBeNull();
        aliceWorkers!.Should().ContainSingle(worker => worker.WorkerId == "worker-alice");

        using var workerResponse = await aliceClient.GetAsync("/api/me/workers/worker-alice");
        workerResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        var workerDetail = await workerResponse.Content.ReadFromJsonAsync<WorkerDetailDto>();
        workerDetail.Should().NotBeNull();
        workerDetail!.WorkerId.Should().Be("worker-alice");

        using var forbiddenWorkerResponse = await aliceClient.GetAsync("/api/me/workers/worker-bob");
        forbiddenWorkerResponse.StatusCode.Should().Be(HttpStatusCode.Forbidden);

        using var forbiddenSessionResponse = await aliceClient.GetAsync($"/api/me/sessions/{bobSession.Response!.SessionId}");
        forbiddenSessionResponse.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    private async Task<string> GetAccessTokenAsync(string username)
    {
        using var client = _factory.CreateClient();
        using var response = await client.PostAsJsonAsync("/api/dev/login", new CortexTerminal.Contracts.Auth.DevLoginRequest(username));
        response.EnsureSuccessStatusCode();
        var payload = await response.Content.ReadFromJsonAsync<CortexTerminal.Contracts.Auth.DevLoginResponse>();
        return payload!.AccessToken;
    }
}
