using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Tests.Auth;
using FluentAssertions;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.DependencyInjection;
using System.Net;
using System.Net.Http.Json;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Tunnels;

public sealed class TunnelEndpointsTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public TunnelEndpointsTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Post_creates_tunnel_and_returns_secret()
    {
        await using var ctx = await SeedAsync();

        using var response = await ctx.Client.PostAsJsonAsync(
            $"/api/me/sessions/{ctx.SessionId}/tunnels",
            new CreateTunnelRequest(3000));

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var dto = await response.Content.ReadFromJsonAsync<TunnelDto>();
        dto.Should().NotBeNull();
        dto!.Port.Should().Be(3000);
        dto.TunnelKey.Should().NotBeNullOrEmpty();
        dto.Secret.Should().NotBeNullOrEmpty();
        dto.Url.Should().Contain(dto.TunnelKey).And.Contain("k=");
    }

    [Fact]
    public async Task Get_lists_active_and_omits_secret()
    {
        await using var ctx = await SeedAsync();

        using (var create = await ctx.Client.PostAsJsonAsync(
            $"/api/me/sessions/{ctx.SessionId}/tunnels",
            new CreateTunnelRequest(3000)))
        {
            create.StatusCode.Should().Be(HttpStatusCode.OK);
        }

        using var listResponse = await ctx.Client.GetAsync($"/api/me/sessions/{ctx.SessionId}/tunnels");
        listResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        var list = await listResponse.Content.ReadFromJsonAsync<TunnelListResponse>();
        list.Should().NotBeNull();
        list!.Tunnels.Should().ContainSingle().Which.Secret.Should().BeNull();
    }

    [Fact]
    public async Task Post_rejects_quota_exceeded()
    {
        await using var ctx = await SeedAsync();
        var url = $"/api/me/sessions/{ctx.SessionId}/tunnels";

        for (var i = 0; i < 3; i++)
        {
            using (var ok = await ctx.Client.PostAsJsonAsync(url, new CreateTunnelRequest(3000 + i)))
            {
                ok.StatusCode.Should().Be(HttpStatusCode.OK);
            }
        }

        using var rejected = await ctx.Client.PostAsJsonAsync(url, new CreateTunnelRequest(9999));
        rejected.StatusCode.Should().Be(HttpStatusCode.TooManyRequests);
    }

    [Fact]
    public async Task Delete_revokes_and_removes_from_list()
    {
        await using var ctx = await SeedAsync();

        TunnelDto created;
        using (var create = await ctx.Client.PostAsJsonAsync(
            $"/api/me/sessions/{ctx.SessionId}/tunnels",
            new CreateTunnelRequest(3000)))
        {
            create.StatusCode.Should().Be(HttpStatusCode.OK);
            created = (await create.Content.ReadFromJsonAsync<TunnelDto>())!;
        }

        using (var delete = await ctx.Client.DeleteAsync($"/api/me/tunnels/{created.TunnelId}"))
        {
            delete.StatusCode.Should().Be(HttpStatusCode.NoContent);
        }

        using (var listResponse = await ctx.Client.GetAsync($"/api/me/sessions/{ctx.SessionId}/tunnels"))
        {
            listResponse.StatusCode.Should().Be(HttpStatusCode.OK);
            var list = await listResponse.Content.ReadFromJsonAsync<TunnelListResponse>();
            list!.Tunnels.Should().BeEmpty();
        }

        using (var again = await ctx.Client.DeleteAsync($"/api/me/tunnels/{created.TunnelId}"))
        {
            again.StatusCode.Should().Be(HttpStatusCode.NotFound);
        }
    }

    private static async Task<SeededContext> SeedAsync()
    {
        var factory = new GatewayApplicationFactory();

        // A live worker hub connection: it registers itself as an online worker owned by
        // "test-user" and answers the port probe so tunnel creation gets past the probe step.
        var worker = factory.CreateAuthenticatedHubConnection("/hubs/worker");
        worker.On<int, ProbePortResponse>("ProbeTunnelPort", _ => new ProbePortResponse(true, null));
        await worker.StartAsync();
        await worker.InvokeAsync("RegisterWorker", "worker-tunnel-test");

        // Create an Attached session bound to that worker. CreateSessionAsync picks the
        // registered worker via TryGetLeastBusyForUser, so the session's WorkerConnectionId
        // matches the worker's live hub connection id.
        var sessions = factory.Services.GetRequiredService<ISessionCoordinator>();
        var created = await sessions.CreateSessionAsync(
            "test-user",
            new CreateSessionRequest("shell", 120, 40),
            clientConnectionId: null,
            CancellationToken.None);
        created.IsSuccess.Should().BeTrue();

        return new SeededContext(
            factory,
            worker,
            factory.CreateAuthenticatedClient(),
            created.Response!.SessionId);
    }

    /// <summary>
    /// Keeps the worker hub connection alive for the whole test — disposing it would
    /// unregister the worker and make the tunnel endpoints fail with 503.
    /// </summary>
    private sealed class SeededContext : IAsyncDisposable
    {
        public GatewayApplicationFactory Factory { get; }
        public HubConnection Worker { get; }
        public HttpClient Client { get; }
        public string SessionId { get; }

        public SeededContext(
            GatewayApplicationFactory factory,
            HubConnection worker,
            HttpClient client,
            string sessionId)
        {
            Factory = factory;
            Worker = worker;
            Client = client;
            SessionId = sessionId;
        }

        public async ValueTask DisposeAsync()
        {
            Client.Dispose();
            await Worker.DisposeAsync();
            await Factory.DisposeAsync();
        }
    }
}
