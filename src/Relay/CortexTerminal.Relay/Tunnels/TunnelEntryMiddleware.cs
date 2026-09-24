using System.Text;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Relay.Workers;
using Microsoft.Extensions.Options;

namespace CortexTerminal.Relay.Tunnels;

/// <summary>
/// 隧道访客 HTTP 入口：拦截 /t/&lt;key&gt;/... 与 t-&lt;key&gt;.&lt;RootDomain&gt; 子域名，
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

        // 子域名模式：Host == "<prefix><key>.<RootDomain>"（默认前缀 "t-"，
        // 配合 DNS 泛解析 *.<RootDomain>；带前缀可避免劫持同域名下其它子域）。
        if (!string.IsNullOrEmpty(opts.RootDomain) && !string.IsNullOrEmpty(host)
            && host.EndsWith("." + opts.RootDomain, StringComparison.OrdinalIgnoreCase))
        {
            var sub = host.Substring(0, host.Length - opts.RootDomain.Length - 1);
            if (!string.IsNullOrEmpty(sub) && sub.IndexOf('.') < 0)
            {
                var prefix = opts.SubdomainPrefix;
                if (prefix.Length > 0)
                {
                    // 带前缀模式：只接受 "<prefix><key>"，其余子域名放行走正常管线。
                    if (sub.StartsWith(prefix, StringComparison.Ordinal))
                    {
                        key = sub.Substring(prefix.Length);
                        subPath = context.Request.Path.Value ?? "/";
                    }
                }
                else
                {
                    // 旧配置（无前缀）：整个子域名即 key。
                    key = sub;
                    subPath = context.Request.Path.Value ?? "/";
                }
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
            await WriteWaitingPageAsync(context,
                "The worker machine is offline. Once it is back online, this page will enter automatically.");
            return;
        }

        var request = new TunnelRequestFrame
        {
            Id = Guid.NewGuid().ToString("N"),
            Port = route.Port,
            RemoteAddress = route.RemoteAddress,
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
            // 响应头与 end 帧同时等：worker 在发出头之前就带错误结束（端口不可达、
            // 等待端口就绪超时等）时，立刻给访客明确的 502，而不是干等 ForwardTimeout。
            var headAwaited = call.Head.Task.WaitAsync(cts.Token);
            var finished = await Task.WhenAny(headAwaited, call.End.Task);
            if (finished != headAwaited)
            {
                var earlyEnd = call.End.Task.Result;
                await WriteWaitingPageAsync(context,
                    earlyEnd.Error is not null
                        ? $"The service on port {route.Port} is not reachable on the worker right now."
                        : "The tunnel closed before a response was produced.");
                return;
            }

            head = await headAwaited;
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

    /// <summary>
    /// 「等待服务就绪」页：503 + 每 5 秒自动刷新（meta refresh），服务一起来自动进入。
    /// 仅对 GET/HEAD 渲染 HTML 页（浏览器场景）；其它方法返回纯文本 503，避免重复提交。
    /// </summary>
    private static async Task WriteWaitingPageAsync(HttpContext context, string message)
    {
        context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
        context.Response.Headers.RetryAfter = "5";
        var isBrowseable = HttpMethods.IsGet(context.Request.Method) || HttpMethods.IsHead(context.Request.Method);
        if (!isBrowseable)
        {
            context.Response.ContentType = "text/plain; charset=utf-8";
            await context.Response.Body.WriteAsync(
                Encoding.UTF8.GetBytes(message + " Retrying automatically."), context.RequestAborted);
            return;
        }

        context.Response.ContentType = "text/html; charset=utf-8";
        var html = $@"<!doctype html>
<html lang=""en"">
<head>
<meta charset=""utf-8"">
<meta name=""viewport"" content=""width=device-width, initial-scale=1"">
<meta http-equiv=""refresh"" content=""5"">
<title>CortexTerminal — waiting for service</title>
<style>
  body {{ font-family: -apple-system, 'Segoe UI', Roboto, sans-serif; background:#0b0f14; color:#f0f3f7;
         display:flex; align-items:center; justify-content:center; min-height:100vh; margin:0; }}
  .card {{ max-width:30rem; padding:2.5rem; text-align:center; }}
  .dot {{ width:10px; height:10px; border-radius:50%; background:#20c997; display:inline-block;
          margin-right:8px; animation:p 1.2s ease-in-out infinite; }}
  @keyframes p {{ 0%,100% {{ opacity:.25; }} 50% {{ opacity:1; }} }}
  h1 {{ font-size:1.25rem; margin:0 0 .75rem; }}
  p {{ color:#98a4b3; line-height:1.6; margin:0 0 1.25rem; }}
  a {{ color:#2498f3; }}
</style>
</head>
<body>
<div class=""card"">
  <h1><span class=""dot""></span>Waiting for service…</h1>
  <p>{System.Net.WebUtility.HtmlEncode(message)}<br>This page refreshes automatically every 5 seconds.</p>
  <p><a href="""">Retry now</a></p>
</div>
</body>
</html>";
        await context.Response.Body.WriteAsync(Encoding.UTF8.GetBytes(html), context.RequestAborted);
    }

    private static async Task WriteErrorAsync(HttpContext context, int status, string message)
    {
        context.Response.StatusCode = status;
        context.Response.ContentType = "text/plain; charset=utf-8";
        await context.Response.Body.WriteAsync(Encoding.UTF8.GetBytes(message), context.RequestAborted);
    }
}
