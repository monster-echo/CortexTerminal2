using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Tunnels;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Tunnels;

public sealed class TunnelRegistryTests
{
    private static async Task<TunnelRegistry> NewRegistryAsync(string dbName)
    {
        var services = new ServiceCollection();
        services.AddDbContextFactory<AppDbContext>(o => o.UseInMemoryDatabase(dbName));
        services.AddSingleton(TimeProvider.System);
        var sp = services.BuildServiceProvider();
        var factory = sp.GetRequiredService<IDbContextFactory<AppDbContext>>();
        await using (var db = await factory.CreateDbContextAsync())
            await db.Database.EnsureCreatedAsync();
        return new TunnelRegistry(factory, TimeProvider.System);
    }

    [Fact]
    public async Task CreateAsync_persists_and_returns_entity_with_generated_ids()
    {
        var reg = await NewRegistryAsync("tun_create");

        var entity = await reg.CreateAsync(
            tunnelKey: "abc",
            secretHash: "deadbeef",
            ownerUserId: "u1",
            workerId: "w1",
            workerConnectionId: "c1",
            sessionId: "s1",
            port: 3000,
            ttl: TimeSpan.FromHours(24));

        entity.Id.Should().NotBeNullOrEmpty();
        entity.TunnelKey.Should().Be("abc");
        entity.ExpiresAtUtc.Should().BeAfter(DateTimeOffset.UtcNow.AddHours(23));
        entity.RevokedAtUtc.Should().BeNull();

        var found = await reg.FindByKeyAsync("abc");
        found.Should().NotBeNull();
        found!.SecretHash.Should().Be("deadbeef");
    }

    [Fact]
    public async Task FindByKeyAsync_skips_revoked()
    {
        var reg = await NewRegistryAsync("tun_revoke");
        var e = await reg.CreateAsync("k1", "h", "u", "w", "c", "s", 1, TimeSpan.FromHours(1));

        (await reg.FindByKeyAsync("k1")).Should().NotBeNull();
        await reg.RevokeAsync(e.Id, "u");
        (await reg.FindByKeyAsync("k1")).Should().BeNull();
    }

    [Fact]
    public async Task ListForSessionAsync_returns_only_active_for_owner()
    {
        var reg = await NewRegistryAsync("tun_list");
        await reg.CreateAsync("k1", "h", "u1", "w", "c", "s1", 1, TimeSpan.FromHours(1));
        await reg.CreateAsync("k2", "h", "u1", "w", "c", "s1", 2, TimeSpan.FromHours(1));
        var revoked = await reg.CreateAsync("k3", "h", "u1", "w", "c", "s1", 3, TimeSpan.FromHours(1));
        await reg.RevokeAsync(revoked.Id, "u1");

        var list = await reg.ListForSessionAsync("s1", "u1");
        list.Should().HaveCount(2);
        list.Select(t => t.TunnelKey).Should().Equal("k1", "k2");
    }

    [Fact]
    public async Task RevokeAsync_returns_false_for_wrong_owner()
    {
        var reg = await NewRegistryAsync("tun_owner");
        var e = await reg.CreateAsync("k", "h", "u1", "w", "c", "s", 1, TimeSpan.FromHours(1));
        (await reg.RevokeAsync(e.Id, "other-user")).Should().BeFalse();
    }

    [Fact]
    public async Task CountActiveForSessionAsync_excludes_revoked()
    {
        var reg = await NewRegistryAsync("tun_count");
        var a = await reg.CreateAsync("k1", "h", "u", "w", "c", "s", 1, TimeSpan.FromHours(1));
        await reg.CreateAsync("k2", "h", "u", "w", "c", "s", 2, TimeSpan.FromHours(1));
        await reg.RevokeAsync(a.Id, "u");
        (await reg.CountActiveForSessionAsync("s")).Should().Be(1);
    }

    [Fact]
    public async Task Workspace_scoped_create_list_count_and_update()
    {
        var reg = await NewRegistryAsync("tun_ws");

        var created = await reg.CreateAsync(
            "k1", "h", "u1", "w", "c", sessionId: "",
            port: 3000, ttl: TimeSpan.FromHours(1),
            workspaceId: "ws1", name: "web", localPort: 8080, remoteAddress: "127.0.0.1");

        created.WorkspaceId.Should().Be("ws1");
        created.Name.Should().Be("web");
        created.LocalPort.Should().Be(8080);
        created.RemoteAddress.Should().Be("127.0.0.1");

        // session 过滤不受 workspace 规则影响（SessionId 留空不会命中）
        (await reg.ListForSessionAsync("s1", "u1")).Should().BeEmpty();
        (await reg.ListForWorkspaceAsync("ws1", "u1")).Should().ContainSingle();
        (await reg.ListForWorkspaceAsync("ws2", "u1")).Should().BeEmpty();
        (await reg.CountActiveForWorkspaceAsync("ws1")).Should().Be(1);

        var updated = await reg.UpdateAsync(created.Id, "u1",
            name: "", localPort: 9090, remoteAddress: "10.0.0.2", remotePort: 5432);
        updated.Should().NotBeNull();
        updated!.Name.Should().BeNull();
        updated.LocalPort.Should().Be(9090);
        updated.RemoteAddress.Should().Be("10.0.0.2");
        updated.Port.Should().Be(5432);

        (await reg.UpdateAsync(created.Id, "other-user", name: "x", localPort: null, remoteAddress: null, remotePort: null))
            .Should().BeNull();
    }
}
