using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using CortexTerminal.Gateway.Membership;

namespace CortexTerminal.Gateway.Data;

public class Plan
{
    [Key]
    [Column("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString("N");

    [Required]
    [StringLength(32)]
    [Column("code")]
    public string Code { get; set; } = "";

    [Required]
    [StringLength(16)]
    [Column("tier")]
    public string Tier { get; set; } = MembershipTiers.Free;

    [Required]
    [StringLength(16)]
    [Column("billing_period")]
    public string BillingPeriod { get; set; } = BillingPeriods.None;

    [Column("price_amount")]
    public decimal PriceAmount { get; set; }

    [Required]
    [StringLength(8)]
    [Column("price_currency")]
    public string PriceCurrency { get; set; } = "CNY";

    [Required]
    [Column("max_workers")]
    public int MaxWorkers { get; set; }

    [Required]
    [Column("max_artifacts_per_session")]
    public int MaxArtifactsPerSession { get; set; }

    [Required]
    [Column("max_artifact_size_bytes")]
    public long MaxArtifactSizeBytes { get; set; }

    [Required]
    [Column("max_artifact_age_days")]
    public int MaxArtifactAgeDays { get; set; }

    [Required]
    [Column("max_scrollback_megabytes")]
    public int MaxScrollbackMegabytes { get; set; }

    [Column("feature_flags")]
    [StringLength(512)]
    public string? FeatureFlags { get; set; }

    [Required]
    [Column("is_active")]
    public bool IsActive { get; set; } = true;

    [Required]
    [Column("sort_order")]
    public int SortOrder { get; set; }

    [Required]
    [Column("created_at_utc")]
    public DateTimeOffset CreatedAtUtc { get; set; } = DateTimeOffset.UtcNow;

    [Required]
    [Column("updated_at_utc")]
    public DateTimeOffset UpdatedAtUtc { get; set; } = DateTimeOffset.UtcNow;
}
