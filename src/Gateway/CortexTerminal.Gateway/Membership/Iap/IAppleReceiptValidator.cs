namespace CortexTerminal.Gateway.Membership.Iap;

/// <summary>
/// Verifies an Apple-signed JWS transaction (<c>signedTransactionInfo</c>) and returns
/// the decoded, trusted fields. Throws <see cref="IapReceiptInvalidException"/> when the
/// signature, certificate chain, bundle id or environment checks fail.
/// </summary>
public interface IAppleReceiptValidator
{
    Task<AppleVerifiedTransaction> VerifyAsync(string signedTransaction, CancellationToken ct);
}
