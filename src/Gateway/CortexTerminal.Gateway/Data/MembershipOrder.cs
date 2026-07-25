using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using CortexTerminal.Gateway.Membership;

namespace CortexTerminal.Gateway.Data;

public class MembershipOrder
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
    [Column("billing_period")]
    public string BillingPeriod { get; set; } = BillingPeriods.None;

    [Column("amount")]
    public decimal Amount { get; set; }

    [Required]
    [StringLength(8)]
    [Column("currency")]
    public string Currency { get; set; } = "CNY";

    [Required]
    [StringLength(16)]
    [Column("channel")]
    public string Channel { get; set; } = OrderChannels.Manual;

    [Required]
    [StringLength(16)]
    [Column("status")]
    public string Status { get; set; } = OrderStatuses.Created;

    [Column("receipt")]
    [StringLength(2048)]
    public string? Receipt { get; set; }

    [Column("provider_order_id")]
    [StringLength(128)]
    public string? ProviderOrderId { get; set; }

    [Required]
    [Column("created_at_utc")]
    public DateTimeOffset CreatedAtUtc { get; set; } = DateTimeOffset.UtcNow;

    [Column("completed_at_utc")]
    public DateTimeOffset? CompletedAtUtc { get; set; }
}
