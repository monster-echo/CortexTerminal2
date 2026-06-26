using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CortexTerminal.Gateway.Data;

public class SessionAgentEventEntity
{
    [Key]
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    [Column("id")]
    public long Id { get; set; }

    [Required]
    [Column("session_id")]
    public string SessionId { get; set; } = "";

    [Required]
    [Column("event_type")]
    [StringLength(64)]
    public string EventType { get; set; } = "";

    [Required]
    [Column("payload")]
    public string PayloadJson { get; set; } = "{}";

    [Required]
    [Column("created_at_utc")]
    public DateTimeOffset CreatedAtUtc { get; set; }
}
