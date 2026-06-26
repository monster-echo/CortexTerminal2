using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CortexTerminal.Gateway.Data;

public class AuditLog
{
    [Key]
    [Column("id")]
    public string Id { get; set; } = "";

    [Required]
    [Column("timestamp")]
    public DateTimeOffset Timestamp { get; set; }

    [Required]
    [Column("user_id")]
    public string UserId { get; set; } = "";

    [Required]
    [Column("user_name")]
    public string UserName { get; set; } = "";

    [Required]
    [Column("action")]
    public string Action { get; set; } = "";

    [Required]
    [Column("target_entity")]
    public string TargetEntity { get; set; } = "";

    [Required]
    [Column("target_id")]
    public string TargetId { get; set; } = "";

    [Column("client_ip")]
    public string? ClientIp { get; set; }

    [Column("user_agent")]
    public string? UserAgent { get; set; }

    [Column("device_model")]
    public string? DeviceModel { get; set; }
}
