using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Tests.Auth;
using FluentAssertions;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.DependencyInjection;
using System.Net;
using System.Net.Http.Json;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Tunnels;

public sealed class WorkspaceTunnelEndpointsTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public WorkspaceTunnelEndpointsTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Create_list_patch_delete_lifecycle()
    {
        await using var ctx = await SeedAsync();
        var baseUri = $"/api/me/workspaces/{ctx.WorkspaceId}/tunnels";

        // create：缺省 remoteAddress → 127.0.0.1；running=true；返回明文 secret
        TunnelDto created;
        using (var create = await ctx.Client.PostAsJsonAsync(baseUri,
            new WorkspaceCreateTunnelRequest("web", 8080, null, 8080)))
        {
            create.StatusCode.Should().Be(HttpStatusCode.OK);
            created = (await create.Content.ReadFromJsonAsync<TunnelDto>())!;
            created.Name.Should().Be("web");
            created.LocalPort.Should().Be(8080);
            created.RemoteAddress.Should().Be("127.0.0.1");
            created.Port.Should().Be(8080);
            created.Running.Should().BeTrue();
            created.WorkspaceId.Should().Be(ctx.WorkspaceId);
            created.Secret.Should().NotBeNullOrEmpty();
            created.Url.Should().Contain(created.TunnelKey);
        }

        // list：secret 不回传
        using (var list = await ctx.Client.GetAsync(baseUri))
        {
            list.StatusCode.Should().Be(HttpStatusCode.OK);
            var parsed = await list.Content.ReadFromJsonAsync<TunnelListResponse>();
            parsed!.Tunnels.Should().ContainSingle().Which.Secret.Should().BeNull();
        }

        // patch：改名 + 改目标端口（url/secret 不随 patch 变化）
        using (var patch = await ctx.Client.PatchAsJsonAsync($"{baseUri}/{created.TunnelId}",
            new WorkspaceUpdateTunnelRequest("api", 9090, "10.0.0.5", 3000)))
        {
            patch.StatusCode.Should().Be(HttpStatusCode.OK);
            var updated = (await patch.Content.ReadFromJsonAsync<TunnelDto>())!;
            updated.TunnelId.Should().Be(created.TunnelId);
            updated.TunnelKey.Should().Be(created.TunnelKey);
            updated.Name.Should().Be("api");
            updated.LocalPort.Should().Be(9090);
            updated.RemoteAddress.Should().Be("10.0.0.5");
            updated.Port.Should().Be(3000);
            // url 不带 secret（编辑响应不回传明文密钥），仅路径部分保持不变。
            updated.Url.Should().Be(created.Url.Substring(0, created.Url.IndexOf('?')));
        }

        // patch 空名 → 清除名称
        using (var patch = await ctx.Client.PatchAsJsonAsync($"{baseUri}/{created.TunnelId}",
            new WorkspaceUpdateTunnelRequest("", null, null, null)))
        {
            patch.StatusCode.Should().Be(HttpStatusCode.OK);
            var updated = (await patch.Content.ReadFromJsonAsync<TunnelDto>())!;
            updated.Name.Should().BeNull();
        }

        // delete 复用 /api/me/tunnels/{id}
        using (var delete = await ctx.Client.DeleteAsync($"/api/me/tunnels/{created.TunnelId}"))
        {
            delete.StatusCode.Should().Be(HttpStatusCode.NoContent);
        }
        using (var list = await ctx.Client.GetAsync(baseUri))
        {
            var parsed = await list.Content.ReadFromJsonAsync<TunnelListResponse>();
            parsed!.Tunnels.Should().BeEmpty();
        }
    }

    [Fact]
    public async Task Create_rejects_out_of_range_ports()
    {
        await using var ctx = await SeedAsync();

        using var bad = await ctx.Client.PostAsJsonAsync(
            $"/api/me/workspaces/{ctx.WorkspaceId}/tunnels",
            new WorkspaceCreateTunnelRequest(null, 0, null, 8080));
        bad.StatusCode.Should().Be(HttpStatusCode.BadRequest);

        using var badRemote = await ctx.Client.PostAsJsonAsync(
            $"/api/me/workspaces/{ctx.WorkspaceId}/tunnels",
            new WorkspaceCreateTunnelRequest(null, 8080, null, 70000));
        badRemote.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Create_returns_not_found_for_unknown_workspace()
    {
        await using var ctx = await SeedAsync();
        using var response = await ctx.Client.PostAsJsonAsync(
            "/api/me/workspaces/ws_missing/tunnels",
            new WorkspaceCreateTunnelRequest(null, 8080, null, 8080));
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Patch_returns_not_found_for_tunnel_in_another_workspace()
    {
        await using var ctx = await SeedAsync();
        TunnelDto created;
        using (var create = await ctx.Client.PostAsJsonAsync(
            $"/api/me/workspaces/{ctx.WorkspaceId}/tunnels",
            new WorkspaceCreateTunnelRequest(null, 8080, null, 8080)))
        {
            created = (await create.Content.ReadFromJsonAsync<TunnelDto>())!;
        }

        var otherWorkspace = await ctx.Workspaces.CreateAsync("test-user", ctx.WorkerId, "other", "/root2");
        using var patch = await ctx.Client.PatchAsJsonAsync(
            $"/api/me/workspaces/{otherWorkspace.Id}/tunnels/{created.TunnelId}",
            new WorkspaceUpdateTunnelRequest(null, null, null, 3000));
        patch.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    private async Task<SeededContext> SeedAsync()
    {
        var factory = new GatewayApplicationFactory();

        // 在线 worker（归 "test-user" 所有），并应答端口 probe。
        var worker = factory.CreateAuthenticatedHubConnection("/hubs/worker");
        worker.On<int, ProbePortResponse>("ProbeTunnelPort", _ => new ProbePortResponse(true, null));
        await worker.StartAsync();
        await worker.InvokeAsync("RegisterWorker", "worker-tunnel-test");

        var workspaces = factory.Services.GetRequiredService<CortexTerminal.Gateway.Workspaces.WorkspaceRegistry>();
        var workspace = await workspaces.CreateAsync("test-user", "worker-tunnel-test", "TunnelTest", "/root");

        return new SeededContext(factory, worker, factory.CreateAuthenticatedClient(), workspace.Id, workspaces, "worker-tunnel-test");
    }

    private sealed class SeededContext : IAsyncDisposable
    {
        public GatewayApplicationFactory Factory { get; }
        public HubConnection Worker { get; }
        public HttpClient Client { get; }
        public string WorkspaceId { get; }
        public CortexTerminal.Gateway.Workspaces.WorkspaceRegistry Workspaces { get; }
        public string WorkerId { get; }

        public SeededContext(
            GatewayApplicationFactory factory,
            HubConnection worker,
            HttpClient client,
            string workspaceId,
            CortexTerminal.Gateway.Workspaces.WorkspaceRegistry workspaces,
            string workerId)
        {
            Factory = factory;
            Worker = worker;
            Client = client;
            WorkspaceId = workspaceId;
            Workspaces = workspaces;
            WorkerId = workerId;
        }

        public async ValueTask DisposeAsync()
        {
            Client.Dispose();
            await Worker.DisposeAsync();
            await Factory.DisposeAsync();
        }
    }
}
