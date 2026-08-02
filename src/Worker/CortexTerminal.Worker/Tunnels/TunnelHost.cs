using System.Net;
using System.Net.Http.Headers;
using System.Net.Sockets;
using CortexTerminal.Contracts.Streaming;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Tunnels;

/// <summary>Worker 端 tunnel 执行器:TCP 端口探活 + HttpClient 反代到 localhost:&lt;port&gt;。</summary>
public sealed class TunnelHost(HttpClient httpClient, ILogger<TunnelHost> logger)
{
    public ProbePortResponse ProbePort(int port, TimeSpan timeout)
    {
        if (port <= 0 || port > 65535)
            return new ProbePortResponse(false, $"invalid port {port}");

        try
        {
            using var tcp = new TcpClient();
            var ar = tcp.BeginConnect(IPAddress.Loopback, port, null, null);
            if (!ar.AsyncWaitHandle.WaitOne(timeout))
                return new ProbePortResponse(false, $"connect to localhost:{port} timed out");
            tcp.EndConnect(ar);
            return new ProbePortResponse(true, null);
        }
        catch (Exception ex)
        {
            logger.LogDebug(ex, "probe localhost:{Port} failed", port);
            return new ProbePortResponse(false, ex.Message);
        }
    }

    public async Task<TunnelHttpResponse> HandleRequestAsync(TunnelHttpRequest req, TimeSpan timeout, CancellationToken ct = default)
    {
        var url = $"http://localhost:{req.Port}{req.Path}{req.Query}";
        try
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(timeout);

            using var upstream = new HttpRequestMessage(new HttpMethod(req.Method), url) { Content = BuildContent(req) };
            foreach (var (name, values) in req.Headers)
            {
                if (name.StartsWith("Host", StringComparison.OrdinalIgnoreCase)) continue;
                if (name.StartsWith("Content-", StringComparison.OrdinalIgnoreCase)) continue; // 由 HttpContent 管
                upstream.Headers.TryAddWithoutValidation(name, values);
            }

            using var resp = await httpClient.SendAsync(upstream, HttpCompletionOption.ResponseHeadersRead, cts.Token);
            var respBody = await resp.Content.ReadAsByteArrayAsync(cts.Token);
            var respHeaders = new Dictionary<string, string[]>();
            foreach (var (name, values) in resp.Headers.Concat(resp.Content.Headers))
            {
                respHeaders[name] = values.ToArray();
            }
            return new TunnelHttpResponse((int)resp.StatusCode, respHeaders, respBody, null);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "tunnel forward to {Url} failed", url);
            return new TunnelHttpResponse(502, new Dictionary<string, string[]>(), Array.Empty<byte>(), $"localhost:{req.Port} unreachable: {ex.Message}");
        }
    }

    private static HttpContent? BuildContent(TunnelHttpRequest req)
    {
        if (req.Body.Length == 0 && req.Method is "GET" or "HEAD" or "DELETE") return null;
        var content = new ByteArrayContent(req.Body);
        // Case-insensitive lookup: visitors may send "content-type" in any casing.
        var contentType = req.Headers.FirstOrDefault(kv => kv.Key.Equals("Content-Type", StringComparison.OrdinalIgnoreCase)).Value;
        if (contentType is { Length: > 0 })
            content.Headers.ContentType = MediaTypeHeaderValue.Parse(contentType[0]);
        return content;
    }
}
