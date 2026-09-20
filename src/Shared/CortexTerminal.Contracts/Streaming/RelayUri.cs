using System;
using System.Collections.Generic;

namespace CortexTerminal.Contracts.Streaming;

/// <summary>
/// Relay 端点的 URI 构造。Relay 公网地址在配置里是 http(s) 形态（同一地址也用于 HTTP 传输端点），
/// 但 WebSocket 连接只接受 ws(s)。这里统一映射，避免各调用点自己拼字符串时漏掉 —— 隧道数据面与
/// Relay 文件传输都曾因为把 http:// 直接交给 ClientWebSocket 而永远连不上。
/// </summary>
public static class RelayUri
{
    public static Uri BuildWebSocketUri(string relayBaseUrl, string path, params KeyValuePair<string, string>[] query)
    {
        var builder = new UriBuilder($"{relayBaseUrl.TrimEnd('/')}/{path.TrimStart('/')}");
        builder.Scheme = builder.Scheme switch
        {
            "http" => "ws",
            "https" => "wss",
            _ => builder.Scheme,
        };

        if (query.Length > 0)
        {
            var parts = new string[query.Length];
            for (var i = 0; i < query.Length; i++)
            {
                parts[i] = $"{Uri.EscapeDataString(query[i].Key)}={Uri.EscapeDataString(query[i].Value)}";
            }
            builder.Query = string.Join("&", parts);
        }

        return builder.Uri;
    }
}