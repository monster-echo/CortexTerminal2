namespace CortexTerminal.Gateway.Membership;

public sealed class MembershipQuotaExceededException : InvalidOperationException
{
    public string ErrorCode { get; }
    public MembershipQuotaExceededException(string message, string errorCode = "quota_exceeded")
        : base(message) => ErrorCode = errorCode;
}

public sealed class RedeemCodeInvalidException : ArgumentException
{
    public const string ErrorCode = "redeem_invalid";
    public RedeemCodeInvalidException(string message) : base(message) { }
}

public sealed class RedeemCodeExhaustedException : InvalidOperationException
{
    public const string ErrorCode = "redeem_exhausted";
    public RedeemCodeExhaustedException(string message) : base(message) { }
}

public sealed class RedeemCodeExpiredException : InvalidOperationException
{
    public const string ErrorCode = "redeem_expired";
    public RedeemCodeExpiredException(string message) : base(message) { }
}

public sealed class RedeemCodeAlreadyUsedException : InvalidOperationException
{
    public const string ErrorCode = "redeem_already_used";
    public RedeemCodeAlreadyUsedException(string message) : base(message) { }
}

public sealed class IapReceiptInvalidException : InvalidOperationException
{
    public const string ErrorCode = "iap_receipt_invalid";
    public IapReceiptInvalidException(string message) : base(message) { }
}
