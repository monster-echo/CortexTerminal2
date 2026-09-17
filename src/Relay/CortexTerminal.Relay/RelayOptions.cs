namespace CortexTerminal.Relay;

/// <summary>Relay 服务配置，绑定 "Relay" 节。与 Gateway 共享 SharedSecret。</summary>
public sealed class RelayOptions
{
    public const string SectionName = "Relay";

    /// <summary>与 Gateway 共享的 HMAC-SHA256 密钥，用于校验 Gateway 签发的短命令牌。</summary>
    public string SharedSecret { get; set; } = string.Empty;

    /// <summary>对外的公网基地址（如 https://relay.corterm.rwecho.top）。Gateway 用它拼传输端点 URL。</summary>
    public string PublicUrl { get; set; } = string.Empty;

    /// <summary>传输配对的最长寿命。超时未配对/未完成的传输被强制清理。</summary>
    public int TransferTtlSeconds { get; set; } = 600;

    /// <summary>等待另一端（Worker WS 或客户端 HTTP）接入的最长时间。</summary>
    public int ClientWaitSeconds { get; set; } = 90;

    /// <summary>单次传输的字节上限，同时是 Kestrel 请求体上限。</summary>
    public long MaxTransferBytes { get; set; } = 2L << 30;
}
