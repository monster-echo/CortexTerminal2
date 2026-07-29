namespace CortexTerminal.Gateway.Membership.Iap;

/// <summary>
/// The decoded, verified view of an App Store Server Notification V2 envelope. Fields are
/// sourced from the decoded <c>ResponseBodyV2DecodedPayload</c> after JWS verification.
/// Kept deliberately small and library-agnostic so tests can stub the verifier without
/// depending on <c>Mimo.AppStoreServerLibrary</c>.
/// </summary>
/// <param name="NotificationType">
/// Apple's notification type, e.g. <c>DID_RENEW</c>, <c>EXPIRED</c>, <c>REFUND</c>,
/// <c>GRACE_PERIOD_EXPIRED</c>, <c>REVOKE</c>, <c>SUBSCRIPTION_RENEWED</c>, <c>PRICE_CHANGE</c>.
/// </param>
/// <param name="Subtype">Apple's subtype (e.g. <c>VOLUNTARY</c>); may be empty.</param>
/// <param name="NotificationUuid">
/// Apple's stable id for this notification. Used as the webhook idempotency key
/// (<c>IapWebhookEvent.ExternalEventId</c>).
/// </param>
/// <param name="SignedTransactionInfo">
/// The embedded <c>Data.SignedTransactionInfo</c> JWS string, or <c>null</c> when Apple sends
/// a notification without a transaction (e.g. <c>TEST</c>). The caller verifies it via
/// <see cref="IAppleReceiptValidator.VerifyAsync"/> to obtain the trusted transaction fields.
/// </param>
public sealed record AppleDecodedNotification(
    string NotificationType,
    string Subtype,
    string NotificationUuid,
    string? SignedTransactionInfo
);
