using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CortexTerminal.Gateway.Data;

/// <summary>
/// One reward row per invited user: when an invited user activates membership for the
/// first time (redeem / IAP / manual grant), the referrer earns extra membership days.
/// </summary>
public class ReferralReward
{
    [Key]
    [Column("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString("N");

    [Required]
    [Column("referrer_user_id")]
    public string ReferrerUserId { get; set; } = "";

    [Required]
    [Column("invited_user_id")]
    public string InvitedUserId { get; set; } = "";

    [Column("invited_username")]
    public string? InvitedUsername { get; set; }

    [Required]
    [Column("reward_days")]
    public int RewardDays { get; set; }

    [Required]
    [StringLength(32)]
    [Column("source")]
    public string Source { get; set; } = "";

    [Required]
    [Column("created_at_utc")]
    public DateTimeOffset CreatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
}
