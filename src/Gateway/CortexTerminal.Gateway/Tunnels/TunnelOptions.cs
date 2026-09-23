namespace CortexTerminal.Gateway.Tunnels;

public sealed class TunnelOptions
{
    public const string SectionName = "Tunnels";

    /// <summary>路径式入口前缀(M1)。M2 改泛域名后此字段废弃。</summary>
    public string RoutePrefix { get; set; } = "/t/";

    /// <summary>子域名模式的根域名,如 "corterm.rwecho.top"。为空则仅用路径式 RoutePrefix。</summary>
    public string? RootDomain { get; set; }

    /// <summary>子域名前缀:访客 URL 形如 https://t-&lt;key&gt;.&lt;RootDomain&gt;/。与 Relay 的 SubdomainPrefix 保持一致。</summary>
    public string SubdomainPrefix { get; set; } = "t-";

    /// <summary>tunnel 默认寿命。</summary>
    public TimeSpan DefaultTtl { get; set; } = TimeSpan.FromHours(24);

    /// <summary>单 session 最多 tunnel 数。</summary>
    public int MaxTunnelsPerSession { get; set; } = 3;

    /// <summary>全局开关。false 时中间件返回 503,创建端点拒绝。可由 env TUNNELS_ENABLED 覆盖。</summary>
    public bool Enabled { get; set; } = true;

    /// <summary>每 tunnel 每秒最大请求数。超限返回 429。</summary>
    public int MaxQpsPerTunnel { get; set; } = 50;

    /// <summary>端口探活超时。</summary>
    public TimeSpan ProbeTimeout { get; set; } = TimeSpan.FromSeconds(2);

    /// <summary>HTTP 转发给 worker 的总超时(含读上游)。</summary>
    public TimeSpan ForwardTimeout { get; set; } = TimeSpan.FromSeconds(30);
}
