namespace CortexTerminal.Gateway.Membership.Iap;

/// <summary>
/// The verified, decoded view of an Apple-signed JWS transaction after signature
/// validation has passed. Fields are sourced directly from the decoded payload.
/// </summary>
/// <param name="OriginalTransactionId">
/// The transaction identifier of the original purchase; stable across subscription
/// renewals. Used as the idempotency key when granting entitlements.
/// </param>
/// <param name="ProductId">The App Store product identifier (e.g. <c>corterm.pro.month</c>).</param>
/// <param name="ExpiresDateMs">
/// UNIX milliseconds at which an auto-renewable subscription expires, or <c>null</c> for
/// non-consumable / consumable purchases that never expire.
/// </param>
/// <param name="Type">
/// The in-app purchase type as reported by Apple (<c>Auto-Renewable Subscription</c>,
/// <c>Non-Consumable</c>, <c>Consumable</c>, ...).
/// </param>
public sealed record AppleVerifiedTransaction(
    string OriginalTransactionId,
    string ProductId,
    long? ExpiresDateMs,
    string Type
);
