using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CortexTerminal.Gateway.Data;

public class WorkerRecord
{
    [Key]
    [Column("worker_id")]
    public string WorkerId { get; set; } = "";

    [Column("owner_user_id")]
    public string? OwnerUserId { get; set; }

    [Column("hostname")]
    public string? Hostname { get; set; }

    [Column("operating_system")]
    public string? OperatingSystem { get; set; }

    [Column("architecture")]
    public string? Architecture { get; set; }

    [Column("name")]
    public string? Name { get; set; }

    [Required]
    [Column("last_seen_at_utc")]
    public DateTimeOffset LastSeenAtUtc { get; set; }

    [Column("first_connected_at_utc")]
    public DateTimeOffset? FirstConnectedAtUtc { get; set; }

    [Required]
    [Column("is_online")]
    public bool IsOnline { get; set; }
}
