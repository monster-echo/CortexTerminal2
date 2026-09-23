namespace CortexTerminal.Relay;

/// <summary>Relay 隧道数据面配置，绑定 "Tunnels" 节（原 Gateway TunnelOptions 的数据面部分）。</summary>
public sealed class RelayTunnelOptions
{
    public const string SectionName = "Tunnels";

    /// <summary>全局熔断开关：只锁公网 tunnel 入口。</summary>
    public bool Enabled { get; set; } = true;

    /// <summary>路径式前缀，如 "/t/"。</summary>
    public string RoutePrefix { get; set; } = "/t/";

    /// <summary>子域名模式的根域名，如 "tunnel.corterm.rwecho.top"。为空则仅用路径式 RoutePrefix。DNS 需指向本服务。</summary>
    public string RootDomain { get; set; } = string.Empty;

    /// <summary>
    /// 子域名前缀：访客 Host 形如 "t-&lt;key&gt;.&lt;RootDomain&gt;"（对应 DNS 泛解析 *.&lt;RootDomain&gt;）。
    /// 非空时只接受带前缀的子域名（避免劫持同域名下其它子域）；置空则退回旧的无前缀 &lt;key&gt;.&lt;RootDomain&gt;。
    /// </summary>
    public string SubdomainPrefix { get; set; } = "t-";

    /// <summary>Gateway 基地址，用于内部 API 查询隧道路由（tunnel key → worker/port/secretHash）。</summary>
    public string GatewayInternalUrl { get; set; } = string.Empty;

    /// <summary>单请求转发超时。</summary>
    public int ForwardTimeoutSeconds { get; set; } = 120;

    /// <summary>路由缓存秒数。撤销隧道后最多缓存期内仍可达。</summary>
    public int RouteCacheSeconds { get; set; } = 5;
}
