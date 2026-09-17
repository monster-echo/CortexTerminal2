namespace CortexTerminal.Gateway.Workspaces;

/// <summary>Relay 数据面配置，绑定 "Relay" 节。与 Relay 服务共享 SharedSecret。</summary>
public sealed class RelayOptions
{
    public const string SectionName = "Relay";

    /// <summary>与 Relay 服务共享的 HMAC-SHA256 密钥，用于签发短命传输令牌。</summary>
    public string SharedSecret { get; set; } = string.Empty;

    /// <summary>Relay 公网基地址（如 https://relay.corterm.rwecho.top），用于拼传输端点 URL 与 Worker WS 地址。</summary>
    public string PublicUrl { get; set; } = string.Empty;

    /// <summary>传输令牌有效期。需覆盖 Worker 连接 + 客户端传输全程。</summary>
    public int TransferTtlSeconds { get; set; } = 600;
}
