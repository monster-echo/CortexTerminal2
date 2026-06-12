using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CortexTerminal.Gateway.Data;

public class UserIdentity
{
    [Key]
    [Column("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString("N");

    [Required]
    [Column("user_id")]
    public string UserId { get; set; } = "";

    [Required]
    [Column("auth_provider")]
    public string AuthProvider { get; set; } = "";

    [Required]
    [Column("auth_provider_id")]
    public string AuthProviderId { get; set; } = "";

    [Column("email")]
    public string? Email { get; set; }

    [Column("phone_normalized")]
    public string? PhoneNormalized { get; set; }

    [Required]
    [Column("created_at_utc")]
    public DateTimeOffset CreatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
}
