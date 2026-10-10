namespace CortexTerminal.Gateway.Membership.Iap;

/// <summary>Trusted fields returned by Huawei's server-side IAP token verification APIs.</summary>
public sealed record HuaweiVerifiedTransaction(
    string PurchaseToken,
    string PurchaseOrderId,
    string ProductId,
    int PurchaseState,
    int ProductKind,
    long? ExpiresDateMs,
    bool? IsSubscriptionValid);

public interface IHuaweiIapValidator
{
    Task<HuaweiVerifiedTransaction> VerifyAsync(string purchaseToken, string productId, CancellationToken ct);
}
