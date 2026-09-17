using System.Text;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Relay.Workers;
using Microsoft.Extensions.Options;

namespace CortexTerminal.Relay.Tunnels;

/// <summary>
/// 隧道访客 HTTP 入口：拦截 /t/&lt;key&gt;/... 与 &lt;key&gt;.&lt;RootDomain&gt; 子域名，
/// 校验访客 secret，经 Worker 持久 WS 流式转发到 localhost:&lt;port&gt;。不缓冲整包。
/// </summary>
public sealed class TunnelEntryMiddleware(RequestDelegate next, ILogger<TunnelEntryMiddleware> logger)
{
    private static readonly HashSet<string> HopByHopHeaders = new(StringComparer.OrdinalIgnoreCase)
    {
        "Connection", "Keep-Alive", "Proxy-Authenticate", "Proxy-Authorization",
        "TE", "Trailer", "Transfer-Encoding", "Upgrade", "Host",
        "Content-Length", // 由转发通道按实际字节数重建
    };

    public async Task InvokeAsync(
        HttpContext context,
        WorkerRelayRegistry workers,
        TunnelRouteResolver routes,
        IOptions<RelayTunnelOptions> options)
    {
        var host = context.Request.Host.Host;
        var opts = options.Value;
        var key = string.Empty;
        var subPath = string.Empty;

        // 子域名模式：Host == "<key>.<RootDomain>"
        if (!string.IsNullOrEmpty(opts.RootDomain) && !string.IsNullOrEmpty(host)
            && host.EndsWith("." + opts.RootDomain, StringComparison.OrdinalIgnoreCase))
        {
            var sub = host.Substring(0, host.Length - opts.RootDomain.Length - 1);
            if (!string.IsNullOrEmpty(sub) && sub.IndexOf('.') < 0)
            {
                key = sub;
                subPath = context.Request.Path.Value ?? "/";
            }
        }

        // 路径式模式：RoutePrefix
        if (string.IsNullOrEmpty(key))
        {
            var path = context.Request.Path.Value ?? string.Empty;
            if (!path.StartsWith(opts.RoutePrefix, StringComparison.Ordinal))
            {
                await next(context);
                return;
            }
            var withoutPrefix = path.Substring(opts.RoutePrefix.Length);
            var slashIdx = withoutPrefix.IndexOf('/');
            key = slashIdx < 0 ? withoutPrefix : withoutPrefix.Substring(0, slashIdx);
            subPath = slashIdx < 0 ? "/" : withoutPrefix.Substring(slashIdx);
        }

        if (string.IsNullOrEmpty(key))
        {
            await WriteErrorAsync(context, StatusCodes.Status404NotFound, "Missing tunnel key.");
            return;
        }

        if (!opts.Enabled)
        {
            await WriteErrorAsync(context, StatusCodes.Status503ServiceUnavailable, "Port forwarding is disabled.");
            return;
        }

        var route = await routes.ResolveAsync(key, context.RequestAborted);
        if (route is null)
        {
            await WriteErrorAsync(context, StatusCodes.Status410Gone, "Tunnel does not exist or has been revoked.");
            return;
        }

        if (route.ExpiresAtUtc <= DateTimeOffset.UtcNow)
        {
            await WriteErrorAsync(context, StatusCodes.Status410Gone, "Tunnel has expired.");
            return;
        }

        var querySecret = context.Request.Query["k"].FirstOrDefault();
        var cookieSecret = context.Request.Cookies["k"];
        var secret = !string.IsNullOrEmpty(querySecret) ? querySecret : (cookieSecret ?? string.Empty);
        if (!TunnelSecret.Verify(secret, route.SecretHash))
        {
            await WriteErrorAsync(context, StatusCodes.Status401Unauthorized, "Invalid or missing tunnel secret.");
            return;
        }

        // 首次经 query 校验通过 → 种 cookie，后续子资源请求(相对路径无 ?k=)带 cookie 免输 secret
        if (string.IsNullOrEmpty(cookieSecret))
        {
            context.Response.Cookies.Append("k", secret, new CookieOptions
            {
                HttpOnly = true,
                Secure = true,
                SameSite = SameSiteMode.Lax,
                Path = "/",
                Expires = route.ExpiresAtUtc,
            });
        }

        var worker = workers.Find(route.WorkerId);
        if (worker is null)
        {
            await WriteErrorAsync(context, StatusCodes.Status502BadGateway,
                "Worker is offline. Start the worker and reattach the session.");
            return;
        }

        var request = new TunnelRequestFrame
        {
            Id = Guid.NewGuid().ToString("N"),
            Port = route.Port,
            Method = context.Request.Method,
            Path = subPath,
            Query = context.Request.QueryString.Value ?? string.Empty,
            Headers = CollectHeaders(context.Request.Headers),
        };

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted);
        cts.CancelAfter(TimeSpan.FromSeconds(opts.ForwardTimeoutSeconds));

        TunnelCall call;
        try
        {
            call = await worker.CallAsync(request, context.Request.Body, cts.Token);
        }
        catch (OperationCanceledException)
        {
            await WriteErrorAsync(context, StatusCodes.Status504GatewayTimeout, "Upstream did not respond in time.");
            return;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Tunnel forward failed for tunnel {TunnelKey}.", key);
            await WriteErrorAsync(context, StatusCodes.Status502BadGateway, "Tunnel forward failed: " + ex.Message);
            return;
        }

        TunnelResponseHeadFrame head;
        try
        {
            head = await call.Head.Task.WaitAsync(cts.Token);
        }
        catch (OperationCanceledException)
        {
            await WriteErrorAsync(context, StatusCodes.Status504GatewayTimeout, "Upstream did not respond in time.");
            return;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Tunnel forward failed for tunnel {TunnelKey}.", key);
            await WriteErrorAsync(context, StatusCodes.Status502BadGateway, "Tunnel forward failed: " + ex.Message);
            return;
        }

        if (head.Status == StatusCodes.Status101SwitchingProtocols)
        {
            // WebSocket 升级无法在二次反代上重建（当前版本限制）
            await WriteErrorAsync(context, StatusCodes.Status501NotImplemented,
                "WebSocket upgrade through tunnels is not supported yet.");
            return;
        }

        context.Response.StatusCode = head.Status;
        foreach (var (name, values) in head.Headers)
        {
            if (HopByHopHeaders.Contains(name)) continue;
            context.Response.Headers.Append(name, values);
        }

        // 响应体流式对拷：Worker 数据帧 → 响应流
        var bodyReader = call.ResponseBody.Reader;
        try
        {
            while (await bodyReader.WaitToReadAsync(cts.Token))
            {
                while (bodyReader.TryRead(out var chunk))
                {
                    await context.Response.Body.WriteAsync(chunk, cts.Token);
                }
            }

            var end = await call.End.Task.WaitAsync(cts.Token);
            if (end.Error is not null)
            {
                // 头已发出：截断连接，客户端按 Content-Length 检测失败
                context.Abort();
            }
        }
        catch (OperationCanceledException) when (!context.Response.HasStarted)
        {
            await WriteErrorAsync(context, StatusCodes.Status504GatewayTimeout, "Upstream did not respond in time.");
        }
    }

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
