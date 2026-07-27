using MessagePack;

namespace CortexTerminal.Contracts.Streaming;

/// <summary>Gateway -> Worker:转发一个 HTTP 请求到 tunnel 绑定的 localhost 端口。</summary>
[MessagePackObject]
public sealed record TunnelHttpRequest(
    [property: Key(0)] string TunnelId,
    [property: Key(1)] int Port,
    [property: Key(2)] string Method,
    [property: Key(3)] string Path,
    [property: Key(4)] string Query,
    [property: Key(5)] Dictionary<string, string[]> Headers,
    [property: Key(6)] byte[] Body);

/// <summary>Worker -> Gateway:HTTP 转发响应。ErrorMessage 非 null 时表示上游错误(此时 StatusCode=502)。</summary>
[MessagePackObject]
public sealed record TunnelHttpResponse(
    [property: Key(0)] int StatusCode,
    [property: Key(1)] Dictionary<string, string[]> Headers,
    [property: Key(2)] byte[] Body,
    [property: Key(3)] string? ErrorMessage);

[MessagePackObject]
public sealed record ProbePortRequest(
    [property: Key(0)] int Port);

[MessagePackObject]
public sealed record ProbePortResponse(
    [property: Key(0)] bool Open,
    [property: Key(1)] string? ErrorMessage);
