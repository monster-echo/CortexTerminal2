namespace CortexTerminal.Mobile.Core.Features.Iap;

/// <summary>
/// The wire format of <see cref="IapPurchaseResult.SignedTransaction"/>, telling the
/// backend which Apple verification path to take.
/// </summary>
public enum IapReceiptFormat
{
    /// <summary>
    /// Apple StoreKit 2 <c>JWSTransaction</c> (header.payload.signature, ES256 + x5c chain),
    /// the format the backend's <c>AppleReceiptValidator</c>
    /// (<c>SignedDataVerifier.VerifyAndDecodeTransaction</c>) currently expects.
    /// </summary>
    AppleJwsTransaction,

    /// <summary>
    /// Apple legacy base64 app-store receipt (the PKCS#7 blob at
    /// <c>NSBundle.AppStoreReceiptUrl</c>), as produced by Plugin.InAppBilling on iOS.
    /// Verified via Apple's legacy <c>/verifyReceipt</c> endpoint, <em>not</em> by the
    /// current backend validator. Surfaced as a distinct format so the caller knows the
    /// backend contract must be extended to accept it.
    /// </summary>
    AppleLegacyReceipt
}

/// <summary>
/// Outcome of a single in-app purchase. <see cref="SignedTransaction"/> is the payload the
/// client forwards to the gateway verify endpoint (<c>POST /api/iap/purchase/verify</c>).
/// </summary>
/// <param name="ProductId">The store product id that was purchased.</param>
/// <param name="State">Plugin-normalized purchase state (e.g. <c>Purchased</c>, <c>Restored</c>).</param>
/// <param name="TransactionIdentifier">Store transaction id; also used to finalize/finish the transaction.</param>
/// <param name="SignedTransaction">The signed payload to send for server-side verification.</param>
/// <param name="ReceiptFormat">Declares which Apple verification path <see cref="SignedTransaction"/> belongs to.</param>
public sealed record IapPurchaseResult(
    string ProductId,
    string State,
    string TransactionIdentifier,
    string SignedTransaction,
    IapReceiptFormat ReceiptFormat);
