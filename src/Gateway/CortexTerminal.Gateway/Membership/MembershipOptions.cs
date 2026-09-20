namespace CortexTerminal.Gateway.Membership;

public sealed class MembershipOptions
{
    public const string SectionName = "Billing";
    public string DefaultCurrency { get; set; } = "CNY";
    public string RedeemCodePrefix { get; set; } = "CORTERM";

    // Free 配额(对齐现有默认值,Free 不降级)
    public int FreeMaxWorkers { get; set; } = 1;
    public int FreeMaxArtifactsPerSession { get; set; } = 100;
    public long FreeMaxArtifactSizeBytes { get; set; } = 50 * 1024 * 1024;
    public int FreeMaxArtifactAgeDays { get; set; } = 7;
    public int FreeMaxScrollbackMegabytes { get; set; } = 5;

    // Pro 配额(建议值,待产品定稿)
    public int ProMaxWorkers { get; set; } = 5;
    public int ProMaxArtifactsPerSession { get; set; } = 500;
    public long ProMaxArtifactSizeBytes { get; set; } = 200 * 1024 * 1024;
    public int ProMaxArtifactAgeDays { get; set; } = 90;
    public int ProMaxScrollbackMegabytes { get; set; } = 20;

    // 价格占位(真实价格在商店后台,此处仅展示)
    public decimal ProMonthPrice { get; set; } = 0m;
    public decimal ProYearPrice { get; set; } = 0m;
    public decimal ProLifetimePrice { get; set; } = 0m;
}
