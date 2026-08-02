using System.Text;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Workers;
using Microsoft.Extensions.Options;

namespace CortexTerminal.Gateway.Tunnels;

/// <summary>访客 HTTP 入口:拦截 /t/&lt;key&gt;/... 路径,校验 secret,经 dispatcher 把请求转发到绑定的 worker。</summary>
public sealed class TunnelMiddleware(RequestDelegate next, ILogger<TunnelMiddleware> logger)
{
    public async Task InvokeAsync(
        HttpContext context,
        TunnelRegistry registry,
        IWorkerRegistry workers,
        IWorkerCommandDispatcher dispatcher,
        IOptions<TunnelOptions> options)
    {
        var path = context.Request.Path.Value ?? string.Empty;
        var prefix = options.Value.RoutePrefix;

        if (!path.StartsWith(prefix, StringComparison.Ordinal))
        {
            await next(context);
            return;
        }

        var withoutPrefix = path.Substring(prefix.Length);
        var slashIdx = withoutPrefix.IndexOf('/');
        var key = slashIdx < 0 ? withoutPrefix : withoutPrefix.Substring(0, slashIdx);
        var subPath = slashIdx < 0 ? "/" : withoutPrefix.Substring(slashIdx);

        if (string.IsNullOrEmpty(key))
        {
            await WriteErrorAsync(context, StatusCodes.Status404NotFound, "Missing tunnel key.");
            return;
        }

        var tunnel = await registry.FindByKeyAsync(key);
        if (tunnel is null)
        {
            await WriteErrorAsync(context, StatusCodes.Status410Gone, "Tunnel does not exist or has been revoked.");
            return;
        }

        if (tunnel.ExpiresAtUtc <= DateTimeOffset.UtcNow)
        {
            await WriteErrorAsync(context, StatusCodes.Status410Gone, "Tunnel has expired.");
            return;
        }

        var secret = context.Request.Query["k"].FirstOrDefault() ?? string.Empty;
        if (!TunnelSecret.Verify(secret, tunnel.SecretHash))
        {
            await WriteErrorAsync(context, StatusCodes.Status401Unauthorized, "Invalid or missing tunnel secret.");
            return;
        }

        if (!workers.TryGetWorker(tunnel.WorkerId, out var worker)
            || !string.Equals(worker.ConnectionId, tunnel.WorkerConnectionId, StringComparison.Ordinal))
        {
            await WriteErrorAsync(context, StatusCodes.Status502BadGateway, "Worker is offline. Start the worker and reattach the session.");
            return;
        }

        var body = await ReadRequestBodyAsync(context.Request, context.RequestAborted);
        var headers = CollectHeaders(context.Request.Headers);
        var tunnelRequest = new TunnelHttpRequest(
            tunnel.Id, tunnel.Port, context.Request.Method, subPath,
            context.Request.QueryString.Value ?? string.Empty,
            headers, body);

        TunnelHttpResponse tunnelResponse;
        try
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted);
            cts.CancelAfter(options.Value.ForwardTimeout);
            tunnelResponse = await dispatcher.SendTunnelHttpRequestAsync(
                worker.ConnectionId, tunnel.Id, tunnelRequest, cts.Token);
        }
        catch (OperationCanceledException)
        {
            await WriteErrorAsync(context, StatusCodes.Status504GatewayTimeout, "Upstream did not respond in time.");
            return;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Tunnel forward failed for tunnel {TunnelId}.", tunnel.Id);
            await WriteErrorAsync(context, StatusCodes.Status502BadGateway, "Tunnel forward failed: " + ex.Message);
            return;
        }

        if (tunnelResponse.ErrorMessage is not null)
        {
            await WriteErrorAsync(context, StatusCodes.Status502BadGateway, tunnelResponse.ErrorMessage);
            return;
        }

        context.Response.StatusCode = tunnelResponse.StatusCode;
        foreach (var (name, values) in tunnelResponse.Headers)
        {
            context.Response.Headers.Append(name, values);
        }
        context.Response.Headers.Remove("Transfer-Encoding");

        if (tunnelResponse.Body.Length > 0)
        {
            await context.Response.Body.WriteAsync(tunnelResponse.Body, context.RequestAborted);
        }
    }

    private static async Task<byte[]> ReadRequestBodyAsync(HttpRequest request, CancellationToken ct)
    {
        if (request.ContentLength is 0) return Array.Empty<byte>();
        using var ms = new MemoryStream();
        await request.Body.CopyToAsync(ms, ct);
        return ms.ToArray();
    }

    private static readonly HashSet<string> HopByHopHeaders = new(StringComparer.OrdinalIgnoreCase)
    {
        "Connection", "Keep-Alive", "Proxy-Authenticate", "Proxy-Authorization",
        "TE", "Trailer", "Transfer-Encoding", "Upgrade", "Host"
    };

    private static Dictionary<string, string[]> CollectHeaders(IHeaderDictionary headers)
    {
        var result = new Dictionary<string, string[]>(headers.Count);
        foreach (var (key, value) in headers)
        {
            if (key.StartsWith("Authorization", StringComparison.OrdinalIgnoreCase)) continue;
            if (HopByHopHeaders.Contains(key)) continue;
            result[key] = value.ToArray()!;
        }
        return result;
    }

    private static async Task WriteErrorAsync(HttpContext context, int status, string message)
    {
        context.Response.StatusCode = status;
        context.Response.ContentType = "text/plain; charset=utf-8";
        await context.Response.Body.WriteAsync(Encoding.UTF8.GetBytes(message), context.RequestAborted);
    }
}
