namespace CortexTerminal.Gateway.Membership.Iap;

/// <summary>
/// Verifies Apple-signed JWS payloads (transaction info and App Store Server Notifications)
/// and returns the decoded, trusted fields. Throws <see cref="IapReceiptInvalidException"/>
/// for transaction verification failures and <see cref="IapWebhookSignatureInvalidException"/>
/// for notification verification failures, so the caller can map them to a 400 instead of
/// silently treating the payload as valid.
/// </summary>
public interface IAppleReceiptValidator
{
    /// <summary>
    /// Verifies a <c>signedTransactionInfo</c> JWS and returns its decoded fields.
    /// </summary>
    Task<AppleVerifiedTransaction> VerifyAsync(string signedTransaction, CancellationToken ct);

    /// <summary>
    /// Verifies an App Store Server Notification V2 <c>signedPayload</c> JWS and returns the
    /// decoded notification envelope (<see cref="AppleDecodedNotification"/>). The embedded
    /// <c>Data.SignedTransactionInfo</c> is returned as a raw JWS string; the caller verifies
    /// it via <see cref="VerifyAsync"/> when it needs the trusted transaction fields.
    /// </summary>
    Task<AppleDecodedNotification> VerifyNotificationAsync(string signedPayload, CancellationToken ct);
}
