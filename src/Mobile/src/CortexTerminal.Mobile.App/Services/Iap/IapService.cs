#if IOS
using CortexTerminal.Mobile.Core.Features.Iap;
using Plugin.InAppBilling;

namespace CortexTerminal.Mobile.App.Services.Iap;

/// <summary>
/// iOS in-app-purchase backed by Plugin.InAppBilling 10.x. On iOS the plugin drives StoreKit 1
/// (<c>SKPaymentQueue</c>), so <see cref="PurchaseAsync"/> returns an
/// <see cref="IapReceiptFormat.AppleLegacyReceipt"/> (base64 of
/// <c>NSBundle.AppStoreReceiptUrl</c>). The gateway's current <c>AppleReceiptValidator</c> requires
/// a StoreKit 2 JWS — see the note on <see cref="IapReceiptFormat"/>; until the backend accepts the
/// legacy receipt this path is surfaced, not silently downgraded.
/// </summary>
public sealed class IapService : IIapService
{
    private readonly IInAppBilling _billing;
    private readonly ItemType _itemType;

    /// <param name="itemType">Default product type for the catalog (subscriptions or one-off).</param>
    public IapService(IInAppBilling billing, ItemType itemType = ItemType.Subscription)
    {
        _billing = billing;
        _itemType = itemType;
    }

    /// <inheritdoc />
    public bool CanMakePayments => _billing.CanMakePayments;

    /// <inheritdoc />
    public async Task<IReadOnlyList<IapProduct>> GetProductsAsync(IReadOnlyList<string> productIds, CancellationToken ct)
    {
        ThrowIfEmpty(productIds);

        await using var conn = await BillingConnection.BeginAsync(_billing, ct).ConfigureAwait(false);
        var products = await _billing.GetProductInfoAsync(_itemType, productIds.ToArray(), ct).ConfigureAwait(false);
        return products.Select(MapProduct).ToList();
    }

    /// <inheritdoc />
    public async Task<IapPurchaseResult> PurchaseAsync(string productId, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(productId))
            throw new ArgumentException("productId is required", nameof(productId));

        await using var conn = await BillingConnection.BeginAsync(_billing, ct).ConfigureAwait(false);
        InAppBillingPurchase purchase;
        try
        {
            purchase = await _billing.PurchaseAsync(productId, _itemType, cancellationToken: ct).ConfigureAwait(false);
        }
        catch (InAppBillingPurchaseException ex)
        {
            // Per project rule: surface the error, do not swallow. Cancellation is a known,
            // non-fatal outcome the caller checks via IapPurchaseException.IsUserCancelled.
            throw new IapPurchaseException(ex.PurchaseError.ToString(), ex.Message);
        }

        return MapPurchase(purchase, _billing.ReceiptData);
    }

    /// <inheritdoc />
    public async Task RestoreAsync(CancellationToken ct)
    {
        await using var conn = await BillingConnection.BeginAsync(_billing, ct).ConfigureAwait(false);
        // Plugin.InAppBilling has no dedicated RestorePurchasesAsync; GetPurchasesAsync re-syncs the
        // user's transactions with the App Store (the SKPaymentQueue observer drives
        // RestoreCompletedTransactions). Entitlement is granted server-side, so we only need to
        // await the sync to completion.
        await _billing.GetPurchasesAsync(_itemType, ct).ConfigureAwait(false);
    }

    private static IapProduct MapProduct(InAppBillingProduct p) => new(
        ProductId: p.ProductId,
        Title: p.Name,
        Description: p.Description,
        LocalizedPrice: p.LocalizedPrice,
        CurrencyCode: p.CurrencyCode ?? string.Empty);

    private static IapPurchaseResult MapPurchase(InAppBillingPurchase p, string appReceipt)
    {
        // Plugin 10.x iOS (StoreKit 1) exposes the signed app receipt on the billing instance
        // (base64 of NSBundle.AppStoreReceiptUrl — an Apple-signed PKCS#7 blob), not on the purchase
        // object. This is the strongest signed artifact the plugin exposes; the per-transaction
        // PurchaseToken (base64 SKPaymentTransaction.TransactionReceipt) is the weaker/deprecated
        // StoreKit-1 blob, so we prefer the app receipt for server verification.
        return new IapPurchaseResult(
            ProductId: p.ProductId,
            State: p.State.ToString(),
            TransactionIdentifier: p.TransactionIdentifier ?? p.Id ?? string.Empty,
            SignedTransaction: appReceipt ?? string.Empty,
            ReceiptFormat: IapReceiptFormat.AppleLegacyReceipt);
    }

    private static void ThrowIfEmpty(IReadOnlyList<string> productIds)
    {
        if (productIds is null || productIds.Count == 0)
            throw new ArgumentException("At least one product id is required", nameof(productIds));
    }

    /// <summary>
    /// Ensures <c>ConnectAsync</c>/<c>DisconnectAsync</c> bracket every billing call, even on
    /// exception. The plugin requires an active connection before any product/purchase API.
    /// </summary>
    private sealed class BillingConnection : IAsyncDisposable
    {
        private readonly IInAppBilling _billing;

        private BillingConnection(IInAppBilling billing)
        {
            _billing = billing;
        }

        internal static async ValueTask<BillingConnection> BeginAsync(IInAppBilling billing, CancellationToken ct)
        {
            var connected = await billing.ConnectAsync(cancellationToken: ct).ConfigureAwait(false);
            if (!connected)
                throw new InvalidOperationException("Could not connect to the platform billing service");
            return new BillingConnection(billing);
        }

        public ValueTask DisposeAsync() => new(_billing.DisconnectAsync(CancellationToken.None));
    }
}
#endif
