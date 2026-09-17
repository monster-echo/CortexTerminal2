using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Json;
using Microsoft.Extensions.Options;

namespace CortexTerminal.Relay.Tunnels;

/// <summary>从 Gateway 内部 API 查回的隧道路由。</summary>
public sealed record TunnelRoute(string WorkerId, int Port, string SecretHash, DateTimeOffset ExpiresAtUtc);

/// <summary>
/// tunnel key → 路由的解析器：调 Gateway 内部 API（X-Relay-Secret 头鉴权，密钥同 Relay:SharedSecret），
/// 短 TTL 缓存。查表是控制面小流量；隧道撤销在缓存过期后即时生效。
/// </summary>
public sealed class TunnelRouteResolver(
    IHttpClientFactory httpClientFactory,
    IOptions<RelayOptions> relayOptions,
    ILogger<TunnelRouteResolver> logger)
{
    private readonly ConcurrentDictionary<string, (TunnelRoute Route, DateTimeOffset FetchedAt)> _cache = new(StringComparer.Ordinal);

    public async Task<TunnelRoute?> ResolveAsync(string tunnelKey, CancellationToken ct)
    {
        if (_cache.TryGetValue(tunnelKey, out var cached)
            && DateTimeOffset.UtcNow - cached.FetchedAt < TimeSpan.FromSeconds(5))
        {
            return cached.Route;
        }

        var client = httpClientFactory.CreateClient("tunnel-routes");
        client.DefaultRequestHeaders.Add("X-Relay-Secret", relayOptions.Value.SharedSecret);

        TunnelRoute? route;
        try
        {
            using var response = await client.GetAsync($"/internal/tunnels/{Uri.EscapeDataString(tunnelKey)}", ct);
            if (response.StatusCode == HttpStatusCode.NotFound || response.StatusCode == HttpStatusCode.Gone)
            {
                route = null;
            }
            else
            {
                response.EnsureSuccessStatusCode();
                route = await response.Content.ReadFromJsonAsync<TunnelRoute>(ct);
            }
        }
        catch (HttpRequestException ex)
        {
            logger.LogWarning(ex, "Tunnel route lookup failed for key {TunnelKey}.", tunnelKey);
            throw;
        }

        if (route is null)
        {
            _cache.TryRemove(tunnelKey, out _);
            return null;
        }
        _cache[tunnelKey] = (route, DateTimeOffset.UtcNow);
        return route;
    }
}
