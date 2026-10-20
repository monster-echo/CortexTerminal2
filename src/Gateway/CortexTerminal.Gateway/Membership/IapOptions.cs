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
    /// <summary>AppGallery Connect app id (same value as appId/client_id). JWT 的 aid 与 JWS 的 applicationId 均用它校验。</summary>
    public string ClientId { get; set; } = "";
    /// <summary>HarmonyOS IAP server root, without a trailing slash.</summary>
    public string RootUrl { get; set; } = "https://iap.cloud.huawei.com";
    /// <summary>Issuer ID of the in-app purchase server key（AGC 盈利 &gt; 应用内支付服务 &gt; 服务端密钥管理）。</summary>
    public string IssuerId { get; set; } = "";
    /// <summary>Key ID of the in-app purchase server key（JWT header 的 kid）。</summary>
    public string KeyId { get; set; } = "";
    /// <summary>
    /// PEM (PKCS#8) content of the in-app purchase server key downloaded from AGC（.p8 文件全文）。
    /// 通过 Iap__Huawei__SubscriptionPrivateKeyP8 注入，勿提交到仓库。
    /// </summary>
    public string SubscriptionPrivateKeyP8 { get; set; } = "";
    /// <summary>HarmonyOS 包名，用于校验订阅 JWS 的 packageName。</summary>
    public string BundleName { get; set; } = "";
    /// <summary>
    /// Base64 (DER) of the Huawei root certificate that anchors the x5c chain of the
    /// subscription JWS. When empty the chain is not pinned and only the payload identity
    /// fields are checked — configure this before enabling real money purchases.
    /// </summary>
    public string SubscriptionJwsRootCertBase64 { get; set; } = "";
    public string ProMonthProductId { get; set; } = "corterm.pro.month";
    public string ProYearProductId { get; set; } = "corterm.pro.year";
    public string ProLifetimeProductId { get; set; } = "corterm.pro.lifetime";
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
