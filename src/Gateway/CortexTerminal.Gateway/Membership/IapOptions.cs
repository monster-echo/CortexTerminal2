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
}
