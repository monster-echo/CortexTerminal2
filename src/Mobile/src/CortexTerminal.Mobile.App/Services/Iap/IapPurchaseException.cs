namespace CortexTerminal.Mobile.App.Services.Iap;

/// <summary>
/// Thrown by <see cref="IIapService.PurchaseAsync"/> for any in-app-purchase failure,
/// including user cancellation (<see cref="IsUserCancelled"/>). Callers surface the message to
/// the user; cancellation is a normal, non-fatal outcome the UI treats as a no-op.
/// </summary>
public sealed class IapPurchaseException : Exception
{
    /// <summary>Plugin-normalized error code carried up from Plugin.InAppBilling (<see cref="PurchaseError"/>).</summary>
    public const string UserCancelled = nameof(UserCancelled);

    public IapPurchaseException(string errorCode, string message) : base(message)
    {
        ErrorCode = errorCode;
    }

    /// <summary>Plugin-normalized error code string (UserCancelled, PaymentInvalid, BillingUnavailable, ...).</summary>
    public string ErrorCode { get; }

    /// <summary>True for user-initiated cancellation, which the UI treats as a no-op.</summary>
    public bool IsUserCancelled => ErrorCode == UserCancelled;
}
