using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using CortexTerminal.Gateway.Membership;

namespace CortexTerminal.Gateway.Data;

public class RedeemCode
{
    [Key]
    [Column("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString("N");

    [Required]
    [StringLength(24)]
    [Column("code")]
    public string Code { get; set; } = "";

    [Required]
    [Column("plan_id")]
    [StringLength(64)]
    public string PlanId { get; set; } = "";

    [Required]
    [StringLength(16)]
    [Column("billing_period")]
    public string BillingPeriod { get; set; } = BillingPeriods.Lifetime;

    [Column("batch_id")]
    [StringLength(64)]
    public string? BatchId { get; set; }

    [Required]
    [Column("max_uses")]
    public int MaxUses { get; set; } = 1;

    [Required]
    [Column("used_count")]
    public int UsedCount { get; set; } = 0;

    [Column("expires_at_utc")]
    public DateTimeOffset? ExpiresAtUtc { get; set; }

    [Required]
    [Column("created_by_user_id")]
    [StringLength(64)]
    public string CreatedByUserId { get; set; } = "";

    [Required]
    [Column("is_active")]
    public bool IsActive { get; set; } = true;

    [Required]
    [Column("created_at_utc")]
    public DateTimeOffset CreatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
}
