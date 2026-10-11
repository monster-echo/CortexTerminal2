namespace CortexTerminal.Gateway.Membership;

public sealed class IapOptions
{
    public const string SectionName = "Iap";
    public GoogleIapOptions Google { get; set; } = new();
    public AppleIapOptions Apple { get; set; } = new();
    public HuaweiIapOptions Huawei { get; set; } = new();
}

public sealed class HuaweiIapOptions
{
    /// <summary>AppGallery Connect app id (same value as appId/client_id).</summary>
    public string ClientId { get; set; } = "";
    /// <summary>AppGallery Connect app secret. Supply through Iap__Huawei__ClientSecret.</summary>
    public string ClientSecret { get; set; } = "";
    /// <summary>Regional Huawei IAP order service root, without a trailing slash.</summary>
    public string OrderRootUrl { get; set; } = "";
    /// <summary>Regional Huawei IAP subscription service root, without a trailing slash.</summary>
    public string SubscriptionRootUrl { get; set; } = "";
    /// <summary>IAP payment public key from AppGallery Connect, base64-encoded SPKI.</summary>
    public string PaymentPublicKey { get; set; } = "";
    public string ProMonthProductId { get; set; } = "corterm.pro.month";
    public string ProYearProductId { get; set; } = "corterm.pro.year";
    public string ProLifetimeProductId { get; set; } = "corterm.pro.lifetime";
    public string TokenUrl { get; set; } = "https://oauth-login.cloud.huawei.com/oauth2/v3/token";
}

public sealed class AppleIapOptions
{
    public string BundleId { get; set; } = "";
    public string IssuerId { get; set; } = "";
    public string KeyId { get; set; } = "";
    public string PrivateKey { get; set; } = "";
    public string Environment { get; set; } = "Production";

    /// <summary>
    /// The shared secret used to authenticate the legacy StoreKit 1
    /// <c>/verifyReceipt</c> call (the <c>password</c> field in the request body).
    /// Required only on the legacy path; the StoreKit 2 JWS validator does not use it.
    /// </summary>
    public string SharedSecret { get; set; } = "";
}

public sealed class GoogleIapOptions
{
    public string PackageName { get; set; } = "";
    public string ServiceAccountEmail { get; set; } = "";
    public string PrivateKey { get; set; } = "";
    public bool AllowTestPurchases { get; set; }
    public string PushAudience { get; set; } = "";
    public string PushServiceAccountEmail { get; set; } = "";
    public string ProMonthProductId { get; set; } = "corterm.pro.month";
    public string ProYearProductId { get; set; } = "corterm.pro.year";
    public string ProLifetimeProductId { get; set; } = "corterm.pro.lifetime";
    public bool IsConfigured => !string.IsNullOrWhiteSpace(PackageName) && !string.IsNullOrWhiteSpace(ServiceAccountEmail) && !string.IsNullOrWhiteSpace(PrivateKey);
    public string? PlanCode(string productId) => productId == ProMonthProductId ? PlanCodes.ProMonth
        : productId == ProYearProductId ? PlanCodes.ProYear : productId == ProLifetimeProductId ? PlanCodes.ProLifetime : null;
}
