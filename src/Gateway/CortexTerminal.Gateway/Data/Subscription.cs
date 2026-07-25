using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using CortexTerminal.Gateway.Membership;

namespace CortexTerminal.Gateway.Data;

public class Subscription
{
    [Key]
    [Column("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString("N");

    [Required]
    [Column("user_id")]
    [StringLength(64)]
    public string UserId { get; set; } = "";

    [Required]
    [Column("plan_id")]
    [StringLength(64)]
    public string PlanId { get; set; } = "";

    [Required]
    [StringLength(16)]
    [Column("status")]
    public string Status { get; set; } = SubscriptionStatuses.Active;

    [Required]
    [StringLength(16)]
    [Column("period")]
    public string Period { get; set; } = BillingPeriods.None;

    [Required]
    [Column("start_at_utc")]
    public DateTimeOffset StartAtUtc { get; set; } = DateTimeOffset.UtcNow;

    [Column("expires_at_utc")]
    public DateTimeOffset? ExpiresAtUtc { get; set; }

    [Required]
    [StringLength(24)]
    [Column("source")]
    public string Source { get; set; } = SubscriptionSources.ManualGrant;

    [Column("source_order_id")]
    [StringLength(64)]
    public string? SourceOrderId { get; set; }

    [Column("source_redeem_code_id")]
    [StringLength(64)]
    public string? SourceRedeemCodeId { get; set; }

    [Column("platform_transaction_id")]
    [StringLength(128)]
    public string? PlatformTransactionId { get; set; }

    [Required]
    [Column("created_at_utc")]
    public DateTimeOffset CreatedAtUtc { get; set; } = DateTimeOffset.UtcNow;

    [Required]
    [Column("updated_at_utc")]
    public DateTimeOffset UpdatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
}
