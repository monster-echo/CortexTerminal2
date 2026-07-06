using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CortexTerminal.Gateway.Data;

public class SessionRecordEntity
{
    [Key]
    [Column("session_id")]
    public string SessionId { get; set; } = "";

    [Required]
    [Column("user_id")]
    public string UserId { get; set; } = "";

    [Required]
    [Column("worker_id")]
    public string WorkerId { get; set; } = "";

    [Column("worker_connection_id")]
    public string? WorkerConnectionId { get; set; }

    [Required]
    [Column("columns")]
    public int Columns { get; set; }

    [Required]
    [Column("rows")]
    public int Rows { get; set; }

    [Required]
    [Column("created_at_utc")]
    public DateTimeOffset CreatedAtUtc { get; set; }

    [Required]
    [Column("last_activity_at_utc")]
    public DateTimeOffset LastActivityAtUtc { get; set; }

    [Required]
    [Column("attachment_state")]
    public string AttachmentState { get; set; } = "Attached";

    [Column("attached_client_connection_id")]
    public string? AttachedClientConnectionId { get; set; }

    [Column("exit_code")]
    public int? ExitCode { get; set; }

    [Column("exit_reason")]
    public string? ExitReason { get; set; }

    [Column("replay_pending")]
    public bool ReplayPending { get; set; }

    [Column("name")]
    [StringLength(100)]
    public string? Name { get; set; }

    [Column("agent_kind")]
    [StringLength(32)]
    public string? AgentKind { get; set; }

    [Column("agent_session_id")]
    public string? AgentSessionId { get; set; }

    [Column("inferred_title")]
    [StringLength(200)]
    public string? InferredTitle { get; set; }

    [Required]
    [Column("bytes_ingested")]
    public long BytesIngested { get; set; }
}
