using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CortexTerminal.Gateway.Data;

public class UserPreference
{
    [Key]
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    [Column("id")]
    public long Id { get; set; }

    [Required]
    [Column("user_id")]
    public string UserId { get; set; } = "";

    [Required]
    [Column("key")]
    public string Key { get; set; } = "";

    [Required]
    [Column("value")]
    public string Value { get; set; } = "";

    [Required]
    [Column("updated_at_utc")]
    public DateTimeOffset UpdatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
}
