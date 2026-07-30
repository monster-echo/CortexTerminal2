namespace CortexTerminal.Gateway.Membership.Iap;

/// <summary>
/// Verifies a legacy StoreKit 1 receipt (the base64 receipt-data blob produced by
/// <c>Plugin.InAppBilling</c> / <c>SKPaymentQueue</c>) against Apple's
/// <c>/verifyReceipt</c> endpoint and returns the trusted fields as the same
/// <see cref="AppleVerifiedTransaction"/> shape the JWS validator produces, so
/// <see cref="MembershipService.GrantFromIapAsync"/> is receipt-format-agnostic.
///
/// Throws <see cref="IapReceiptInvalidException"/> for any non-zero Apple status or a
/// missing transaction entry, so the caller maps it to a 400 rather than silently
/// treating the receipt as valid.
/// </summary>
public interface IAppleLegacyReceiptValidator
{
    /// <summary>
    /// POSTs the base64 receipt data to Apple's <c>/verifyReceipt</c> (production first,
    /// sandbox retry on status 21007) and returns the last transaction entry.
    /// </summary>
    Task<AppleVerifiedTransaction> VerifyAsync(string receiptDataBase64, CancellationToken ct);
}
