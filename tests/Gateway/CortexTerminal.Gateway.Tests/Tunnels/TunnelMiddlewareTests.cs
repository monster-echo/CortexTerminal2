using System.Net;
using System.Text;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Tunnels;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using NSubstitute;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Tunnels;

/// <summary>
/// Visitor-facing /t/&lt;key&gt;/ entry point. Visitors carry no JWT — the middleware validates
/// the tunnel secret itself, so these tests hit it without any auth header.
/// </summary>
public sealed class TunnelMiddlewareTests
{
    [Fact]
    public async Task Get_without_secret_returns_401()
    {
        await using var ctx = await SeedAsync();

        using var response = await ctx.Client.GetAsync($"/t/{ctx.Tunnel.TunnelKey}/");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Get_with_wrong_secret_returns_401()
    {
        await using var ctx = await SeedAsync();

        using var response = await ctx.Client.GetAsync($"/t/{ctx.Tunnel.TunnelKey}/?k=wrong-secret");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Get_for_unknown_key_returns_410()
    {
        await using var ctx = await SeedAsync();

        using var response = await ctx.Client.GetAsync("/t/unknown-key/?k=whatever");

        response.StatusCode.Should().Be(HttpStatusCode.Gone);
    }

    [Fact]
    public async Task Get_for_revoked_tunnel_returns_410()
    {
        await using var ctx = await SeedAsync();

        var revoked = await ctx.Factory.Services
            .GetRequiredService<TunnelRegistry>()
            .RevokeAsync(ctx.Tunnel.TunnelId, "test-user");
        revoked.Should().BeTrue();

        using var response = await ctx.Client.GetAsync($"/t/{ctx.Tunnel.TunnelKey}/?k={ctx.Tunnel.Secret}");

        response.StatusCode.Should().Be(HttpStatusCode.Gone);
    }

    [Fact]
    public async Task Get_dispatches_request_to_worker_and_writes_response_body()
    {
        await using var ctx = await SeedAsync();

        var body = Encoding.UTF8.GetBytes("hello from worker");
        var captured = new List<TunnelHttpRequest>();
        ctx.Factory.Dispatcher
            .SendTunnelHttpRequestAsync(
                ctx.Tunnel.WorkerConnectionId,
                ctx.Tunnel.TunnelId,
                Arg.Do<TunnelHttpRequest>(r => captured.Add(r)),
                Arg.Any<CancellationToken>())
            .Returns(new TunnelHttpResponse(
                200,
                new Dictionary<string, string[]> { ["X-Tunnel-Id"] = [ctx.Tunnel.TunnelId] },
                body,
                null));

        using var response = await ctx.Client.GetAsync($"/t/{ctx.Tunnel.TunnelKey}/?k={ctx.Tunnel.Secret}");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        (await response.Content.ReadAsStringAsync()).Should().Be("hello from worker");
        response.Headers.TryGetValues("X-Tunnel-Id", out var headerValues).Should().BeTrue();
        headerValues.Should().Contain(ctx.Tunnel.TunnelId);

        captured.Should().ContainSingle();
        captured[0].Method.Should().Be("GET");
        captured[0].Path.Should().Be("/");
        captured[0].Port.Should().Be(ctx.Tunnel.Port);
        captured[0].Query.Should().Be($"?k={ctx.Tunnel.Secret}");
        captured[0].Headers.Should().NotContainKey("Authorization");
    }

    [Fact]
    public async Task Get_with_multi_segment_subpath_preserves_path()
    {
        await using var ctx = await SeedAsync();

        var captured = new List<TunnelHttpRequest>();
        ctx.Factory.Dispatcher
            .SendTunnelHttpRequestAsync(
                ctx.Tunnel.WorkerConnectionId,
                ctx.Tunnel.TunnelId,
                Arg.Do<TunnelHttpRequest>(r => captured.Add(r)),
                Arg.Any<CancellationToken>())
            .Returns(new TunnelHttpResponse(200, new Dictionary<string, string[]>(), Array.Empty<byte>(), null));

        using var response = await ctx.Client.GetAsync($"/t/{ctx.Tunnel.TunnelKey}/foo/bar?k={ctx.Tunnel.Secret}");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        captured.Should().ContainSingle();
        captured[0].Path.Should().Be("/foo/bar");
    }

    [Fact]
    public async Task Get_when_worker_offline_returns_502()
    {
        await using var ctx = await SeedAsync(workerOnline: false);

        using var response = await ctx.Client.GetAsync($"/t/{ctx.Tunnel.TunnelKey}/?k={ctx.Tunnel.Secret}");

        response.StatusCode.Should().Be(HttpStatusCode.BadGateway);
    }

    [Fact]
    public async Task Get_when_disabled_returns_503()
    {
        await using var ctx = await SeedAsync(settings: new Dictionary<string, string>
        {
            ["Tunnels:Enabled"] = "false",
        });

        using var response = await ctx.Client.GetAsync($"/t/{ctx.Tunnel.TunnelKey}/?k={ctx.Tunnel.Secret}");

        response.StatusCode.Should().Be(HttpStatusCode.ServiceUnavailable);
    }

    [Fact]
    public async Task Get_over_rate_limit_returns_429()
    {
        await using var ctx = await SeedAsync(settings: new Dictionary<string, string>
        {
            ["Tunnels:MaxQpsPerTunnel"] = "2",
        });
        ctx.Factory.Dispatcher
            .SendTunnelHttpRequestAsync(
                ctx.Tunnel.WorkerConnectionId,
                ctx.Tunnel.TunnelId,
                Arg.Any<TunnelHttpRequest>(),
                Arg.Any<CancellationToken>())
            .Returns(new TunnelHttpResponse(200, new Dictionary<string, string[]>(), Array.Empty<byte>(), null));

        using (var first = await ctx.Client.GetAsync($"/t/{ctx.Tunnel.TunnelKey}/?k={ctx.Tunnel.Secret}"))
        {
            first.StatusCode.Should().Be(HttpStatusCode.OK);
        }
        using (var second = await ctx.Client.GetAsync($"/t/{ctx.Tunnel.TunnelKey}/?k={ctx.Tunnel.Secret}"))
        {
            second.StatusCode.Should().Be(HttpStatusCode.OK);
        }
        using var third = await ctx.Client.GetAsync($"/t/{ctx.Tunnel.TunnelKey}/?k={ctx.Tunnel.Secret}");

        third.StatusCode.Should().Be(HttpStatusCode.TooManyRequests);
    }

    [Fact]
    public async Task Get_via_subdomain_host_preserves_full_path_and_dispatches()
    {
        await using var ctx = await SeedAsync();
        ctx.Client.DefaultRequestHeaders.Host = $"{ctx.Tunnel.TunnelKey}.tunnel.test";

        var body = Encoding.UTF8.GetBytes("hello from worker");
        var captured = new List<TunnelHttpRequest>();
        ctx.Factory.Dispatcher
            .SendTunnelHttpRequestAsync(
                ctx.Tunnel.WorkerConnectionId,
                ctx.Tunnel.TunnelId,
                Arg.Do<TunnelHttpRequest>(r => captured.Add(r)),
                Arg.Any<CancellationToken>())
            .Returns(new TunnelHttpResponse(
                200,
                new Dictionary<string, string[]> { ["X-Tunnel-Id"] = [ctx.Tunnel.TunnelId] },
                body,
                null));

        using var response = await ctx.Client.GetAsync($"/foo/bar?k={ctx.Tunnel.Secret}");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        (await response.Content.ReadAsStringAsync()).Should().Be("hello from worker");

        captured.Should().ContainSingle();
        captured[0].Method.Should().Be("GET");
        captured[0].Path.Should().Be("/foo/bar");
        captured[0].Query.Should().Be($"?k={ctx.Tunnel.Secret}");
        captured[0].Port.Should().Be(ctx.Tunnel.Port);
    }

    [Fact]
    public async Task Get_via_subdomain_host_root_path_dispatches()
    {
        await using var ctx = await SeedAsync();
        ctx.Client.DefaultRequestHeaders.Host = $"{ctx.Tunnel.TunnelKey}.tunnel.test";

        var captured = new List<TunnelHttpRequest>();
        ctx.Factory.Dispatcher
            .SendTunnelHttpRequestAsync(
                ctx.Tunnel.WorkerConnectionId,
                ctx.Tunnel.TunnelId,
                Arg.Do<TunnelHttpRequest>(r => captured.Add(r)),
                Arg.Any<CancellationToken>())
            .Returns(new TunnelHttpResponse(200, new Dictionary<string, string[]>(), Array.Empty<byte>(), null));

        using var response = await ctx.Client.GetAsync($"/?k={ctx.Tunnel.Secret}");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        captured.Should().ContainSingle();
        captured[0].Path.Should().Be("/");
    }

    private static async Task<SeededContext> SeedAsync(
        bool workerOnline = true,
        IReadOnlyDictionary<string, string>? settings = null)
    {
        var factory = new TunnelMiddlewareFactory(settings);
        // CreateClient starts the host so Services (and the in-memory TunnelRegistry) is live.
        var client = factory.CreateClient();
        var tunnel = await factory.SeedTunnelAsync();

        if (workerOnline)
        {
            var worker = new RegisteredWorker(tunnel.WorkerId, tunnel.WorkerConnectionId);
            factory.Workers
                .TryGetWorker(tunnel.WorkerId, out Arg.Any<RegisteredWorker>())
                .Returns(ci =>
                {
                    ci[1] = worker;
                    return true;
                });
        }
        else
        {
            factory.Workers
                .TryGetWorker(Arg.Any<string>(), out Arg.Any<RegisteredWorker>())
                .Returns(false);
        }

        return new SeededContext(factory, client, tunnel);
    }

    private sealed class SeededContext(TunnelMiddlewareFactory factory, HttpClient client, SeededTunnel tunnel) : IAsyncDisposable
    {
        public TunnelMiddlewareFactory Factory { get; } = factory;
        public HttpClient Client { get; } = client;
        public SeededTunnel Tunnel { get; } = tunnel;

        public async ValueTask DisposeAsync()
        {
            Client.Dispose();
            await Factory.DisposeAsync();
        }
    }
}

/// <summary>Custom factory: replaces the worker registry + command dispatcher with NSubstitute mocks.</summary>
internal sealed class TunnelMiddlewareFactory : WebApplicationFactory<Program>
{
    private readonly IReadOnlyDictionary<string, string>? _settings;

    public TunnelMiddlewareFactory(IReadOnlyDictionary<string, string>? settings = null)
    {
        _settings = settings;
    }

    public IWorkerRegistry Workers { get; } = Substitute.For<IWorkerRegistry>();
    public IWorkerCommandDispatcher Dispatcher { get; } = Substitute.For<IWorkerCommandDispatcher>();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.UseSetting("Database:UseInMemory", "true");
        builder.UseSetting("Database:InMemoryDbName", $"corterm_gateway_test_{Guid.NewGuid():N}");
        builder.UseSetting("Tunnels:RootDomain", "tunnel.test");
        if (_settings is not null)
        {
            foreach (var (key, value) in _settings)
            {
                builder.UseSetting(key, value);
            }
        }

        builder.ConfigureServices(services =>
        {
            // Last registration wins: these replace the SignalR dispatcher / Postgres registry.
            services.AddSingleton(Workers);
            services.AddSingleton(Dispatcher);
        });
    }

    /// <summary>Seed a tunnel directly through the live TunnelRegistry. Returns the plaintext secret for requests.</summary>
    public async Task<SeededTunnel> SeedTunnelAsync(
        string workerId = "worker-tunnel-test",
        string workerConnectionId = "worker-conn",
        int port = 3000)
    {
        var secret = TunnelSecret.GenerateSecret();
        var key = TunnelSecret.GenerateTunnelKey();
        var registry = Services.GetRequiredService<TunnelRegistry>();
        var entity = await registry.CreateAsync(
            key, TunnelSecret.Hash(secret), "test-user",
            workerId, workerConnectionId, "session-1", port, TimeSpan.FromHours(24));
        return new SeededTunnel(entity.Id, key, secret, workerId, workerConnectionId, port);
    }
}

internal sealed record SeededTunnel(
    string TunnelId,
    string TunnelKey,
    string Secret,
    string WorkerId,
    string WorkerConnectionId,
    int Port);
