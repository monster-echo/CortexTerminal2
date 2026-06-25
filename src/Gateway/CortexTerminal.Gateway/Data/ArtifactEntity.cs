using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CortexTerminal.Gateway.Data;

public class ArtifactEntity
{
    [Key]
    [Column("id")]
    public string Id { get; set; } = "";

    [Required]
    [Column("session_id")]
    public string SessionId { get; set; } = "";

    [Required]
    [Column("filename")]
    [StringLength(255)]
    public string Filename { get; set; } = "";

    [Required]
    [Column("size_bytes")]
    public long SizeBytes { get; set; }

    [Required]
    [Column("status")]
    [StringLength(16)]
    public string Status { get; set; } = "pending";

    [Required]
    [Column("origin")]
    [StringLength(16)]
    public string Origin { get; set; } = "console";

    [Required]
    [Column("owner_user_id")]
    public string OwnerUserId { get; set; } = "";

    [Column("content_sha256")]
    [StringLength(64)]
    public string? ContentSha256 { get; set; }

    [Required]
    [Column("file_category")]
    [StringLength(16)]
    public string FileCategory { get; set; } = "unknown";

    [Required]
    [Column("created_at_utc")]
    public DateTimeOffset CreatedAtUtc { get; set; }

    [Column("completed_at_utc")]
    public DateTimeOffset? CompletedAtUtc { get; set; }

    [Required]
    [Column("expires_at_utc")]
    public DateTimeOffset ExpiresAtUtc { get; set; }
}
