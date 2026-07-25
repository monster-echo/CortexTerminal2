using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace CortexTerminal.Gateway.Data;

public class RedeemCodeUsage
{
    [Key]
    [Column("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString("N");

    [Required]
    [Column("redeem_code_id")]
    [StringLength(64)]
    public string RedeemCodeId { get; set; } = "";

    [Required]
    [Column("user_id")]
    [StringLength(64)]
    public string UserId { get; set; } = "";

    [Required]
    [Column("order_id")]
    [StringLength(64)]
    public string OrderId { get; set; } = "";

    [Required]
    [Column("subscription_id")]
    [StringLength(64)]
    public string SubscriptionId { get; set; } = "";

    [Required]
    [Column("redeemed_at_utc")]
    public DateTimeOffset RedeemedAtUtc { get; set; } = DateTimeOffset.UtcNow;
}
