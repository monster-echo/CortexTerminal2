using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CortexTerminal.Gateway.Data;

public class TunnelEntity
{
    [Key]
    [Column("id")]
    public string Id { get; set; } = "";

    [Required]
    [Column("tunnel_key")]
    [StringLength(16)]
    public string TunnelKey { get; set; } = "";

    [Required]
    [Column("owner_user_id")]
    public string OwnerUserId { get; set; } = "";

    [Required]
    [Column("workspace_id")]
    public string WorkspaceId { get; set; } = "";

    /// <summary>规则名称（可选）；session 级快捷隧道为 null。</summary>
    [Column("name")]
    public string? Name { get; set; }

    /// <summary>访问入口端口标识（展示用）。</summary>
    [Required]
    [Column("local_port")]
    public int LocalPort { get; set; }

    /// <summary>Worker 侧目标地址，默认 127.0.0.1。</summary>
    [Required]
    [Column("remote_address")]
    [StringLength(255)]
    public string RemoteAddress { get; set; } = "127.0.0.1";

    [Required]
    [Column("worker_id")]
    [StringLength(64)]
    public string WorkerId { get; set; } = "";

    [Required]
    [Column("worker_connection_id")]
    [StringLength(64)]
    public string WorkerConnectionId { get; set; } = "";

    [Required]
    [Column("session_id")]
    public string SessionId { get; set; } = "";

    [Required]
    [Column("port")]
    public int Port { get; set; }

    [Required]
    [Column("secret_hash")]
    [StringLength(64)]
    public string SecretHash { get; set; } = "";

    [Required]
    [Column("transport_type")]
    [StringLength(16)]
    public string TransportType { get; set; } = "http";

    [Required]
    [Column("expires_at_utc")]
    public DateTimeOffset ExpiresAtUtc { get; set; }

    [Required]
    [Column("created_at_utc")]
    public DateTimeOffset CreatedAtUtc { get; set; }

    [Column("revoked_at_utc")]
    public DateTimeOffset? RevokedAtUtc { get; set; }
}
