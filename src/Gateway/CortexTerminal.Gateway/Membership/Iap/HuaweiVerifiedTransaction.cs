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
    /// <summary>终身买断（非消耗型）：订单状态查询。</summary>
    Task<HuaweiVerifiedTransaction> VerifyAsync(string purchaseToken, string purchaseOrderId, string productId, CancellationToken ct);

    /// <summary>订单状态查询（不限制商品类型，供服务端通知等场景使用）。</summary>
    Task<HuaweiVerifiedTransaction> VerifyOrderAsync(string purchaseToken, string purchaseOrderId, string productId, int expectedKind, CancellationToken ct);

    /// <summary>订阅状态查询（购买令牌 + 订单号）。</summary>
    Task<HuaweiVerifiedTransaction> VerifySubscriptionStatusAsync(string purchaseOrderId, string purchaseToken, string productId, CancellationToken ct);

    /// <summary>
    /// Verifies the JWS that IAP Kit's <c>createPurchase</c> returns for auto-renewable
    /// subscriptions (PurchaseData.jwsSubscriptionStatus, an ES256 SubGroupStatusPayload).
    /// </summary>
    Task<HuaweiVerifiedTransaction> VerifySubscriptionJwsAsync(string jws, string productId, CancellationToken ct);
}
