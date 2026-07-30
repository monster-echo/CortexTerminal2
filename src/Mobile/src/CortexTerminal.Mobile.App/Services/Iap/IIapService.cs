using CortexTerminal.Mobile.Core.Features.Iap;

namespace CortexTerminal.Mobile.App.Services.Iap;

/// <summary>
/// Abstracts platform in-app purchase (products, purchase, restore). The iOS implementation
/// wraps Plugin.InAppBilling (StoreKit 1). See <see cref="IapPurchaseResult.ReceiptFormat"/>
/// for the signed-payload contract the gateway verify endpoint must accept.
/// </summary>
public interface IIapService
{
    /// <summary>
    /// Whether the user is allowed to make payments (parental controls / device management).
    /// </summary>
    bool CanMakePayments { get; }

    /// <summary>
    /// Fetch displayable product metadata (title/price) for the given product ids.
    /// Unknown ids are dropped by the store.
    /// </summary>
    Task<IReadOnlyList<IapProduct>> GetProductsAsync(IReadOnlyList<string> productIds, CancellationToken ct);

    /// <summary>
    /// Trigger a StoreKit purchase for <paramref name="productId"/>. The returned
    /// <see cref="IapPurchaseResult.SignedTransaction"/> is what the client forwards to the
    /// gateway for server-side verification.
    /// </summary>
    /// <exception cref="IapPurchaseException">User cancelled, payment invalid, or any store error.</exception>
    Task<IapPurchaseResult> PurchaseAsync(string productId, CancellationToken ct);

    /// <summary>
    /// Ask the store to re-deliver the user's previous purchases (App Store syncs
    /// transactions back to the device). Entitlement is reconciled server-side.
    /// </summary>
    Task RestoreAsync(CancellationToken ct);
}
