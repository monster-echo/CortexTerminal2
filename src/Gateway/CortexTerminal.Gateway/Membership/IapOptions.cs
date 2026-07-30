namespace CortexTerminal.Gateway.Membership;

public sealed class IapOptions
{
    public const string SectionName = "Iap";
    public AppleIapOptions Apple { get; set; } = new();
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
