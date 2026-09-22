namespace CortexTerminal.Gateway.Membership;

public sealed class ReferralCodeInvalidException : ArgumentException
{
    public const string ErrorCode = "referral_invalid";
    public ReferralCodeInvalidException(string message) : base(message) { }
}

public sealed class ReferralAlreadyAppliedException : InvalidOperationException
{
    public const string ErrorCode = "referral_already_applied";
    public ReferralAlreadyAppliedException(string message) : base(message) { }
}
