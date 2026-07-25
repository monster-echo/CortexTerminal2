using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CortexTerminal.Gateway.Data;

public class IapWebhookEvent
{
    [Key]
    [Column("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString("N");

    [Required]
    [StringLength(16)]
    [Column("platform")]
    public string Platform { get; set; } = "";

    [Required]
    [Column("external_event_id")]
    [StringLength(128)]
    public string ExternalEventId { get; set; } = "";

    [Required]
    [Column("raw_payload")]
    public string RawPayload { get; set; } = "";

    [Required]
    [Column("received_at_utc")]
    public DateTimeOffset ReceivedAtUtc { get; set; } = DateTimeOffset.UtcNow;

    [Required]
    [Column("processed")]
    public bool Processed { get; set; } = false;
}
