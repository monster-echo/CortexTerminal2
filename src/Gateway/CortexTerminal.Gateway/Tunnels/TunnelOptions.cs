namespace CortexTerminal.Gateway.Tunnels;

public sealed class TunnelOptions
{
    public const string SectionName = "Tunnels";

    /// <summary>路径式入口前缀(M1)。M2 改泛域名后此字段废弃。</summary>
    public string RoutePrefix { get; set; } = "/t/";

    /// <summary>tunnel 默认寿命。</summary>
    public TimeSpan DefaultTtl { get; set; } = TimeSpan.FromHours(24);

    /// <summary>单 session 最多 tunnel 数。</summary>
    public int MaxTunnelsPerSession { get; set; } = 3;

    /// <summary>端口探活超时。</summary>
    public TimeSpan ProbeTimeout { get; set; } = TimeSpan.FromSeconds(2);

    /// <summary>HTTP 转发给 worker 的总超时(含读上游)。</summary>
    public TimeSpan ForwardTimeout { get; set; } = TimeSpan.FromSeconds(30);
}
