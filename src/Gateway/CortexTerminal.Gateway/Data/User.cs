using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CortexTerminal.Gateway.Data;

public class User
{
    [Key]
    [Column("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString("N");

    [Required]
    [Column("username")]
    public string Username { get; set; } = "";

    [Column("email")]
    public string? Email { get; set; }

    [Column("display_name")]
    public string? DisplayName { get; set; }

    [Column("avatar_url")]
    public string? AvatarUrl { get; set; }

    [Column("avatar_data")]
    public byte[]? AvatarData { get; set; }

    [Column("avatar_content_type")]
    public string? AvatarContentType { get; set; }

    [Required]
    [Column("role")]
    public string Role { get; set; } = "user";

    [Required]
    [Column("status")]
    public string Status { get; set; } = "active";

    [Column("auth_provider")]
    public string? AuthProvider { get; set; }

    [Column("auth_provider_id")]
    public string? AuthProviderId { get; set; }

    [Column("password_hash")]
    public string? PasswordHash { get; set; }

    [Column("apple_refresh_token")]
    public string? AppleRefreshToken { get; set; }

    [Column("deleted_at_utc")]
    public DateTimeOffset? DeletedAtUtc { get; set; }

    [Required]
    [Column("created_at_utc")]
    public DateTimeOffset CreatedAtUtc { get; set; } = DateTimeOffset.UtcNow;

    [Required]
    [Column("updated_at_utc")]
    public DateTimeOffset UpdatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
}
