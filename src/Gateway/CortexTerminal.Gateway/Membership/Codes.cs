namespace CortexTerminal.Gateway.Membership;

public static class MembershipTiers
{
    public const string Free = "free";
    public const string Pro = "pro";
}

public static class BillingPeriods
{
    public const string None = "none";
    public const string Monthly = "monthly";
    public const string Yearly = "yearly";
    public const string Lifetime = "lifetime";
}

public static class PlanCodes
{
    public const string Free = "free";
    public const string ProMonth = "pro_month";
    public const string ProYear = "pro_year";
    public const string ProLifetime = "pro_lifetime";
}

public static class SubscriptionStatuses
{
    public const string Active = "active";
    public const string GracePeriod = "grace_period";
    public const string AccountHold = "account_hold";
    public const string Expired = "expired";
    public const string Cancelled = "cancelled";
    public const string Revoked = "revoked";
}

public static class OrderChannels
{
    public const string Manual = "manual";
    public const string Redeem = "redeem";
    public const string IapApple = "iap_apple";
    public const string IapGoogle = "iap_google";
    public const string IapHuawei = "iap_huawei";
    public const string Stripe = "stripe";
}

public static class OrderStatuses
{
    public const string Created = "created";
    public const string Completed = "completed";
    public const string Failed = "failed";
    public const string Refunded = "refunded";
}

public static class SubscriptionSources
{
    public const string ManualGrant = "manual_grant";
    public const string Redeem = "redeem";
    public const string IapApple = "iap_apple";
    public const string IapGoogle = "iap_google";
    public const string IapHuawei = "iap_huawei";
}

public static class AppleProductIds
{
    public const string ProMonth = "corterm.pro.month";
    public const string ProYear = "corterm.pro.year";
    public const string ProLifetime = "corterm.pro.lifetime";

    public static string? ToPlanCode(string productId) => productId switch
    {
        ProMonth => PlanCodes.ProMonth,
        ProYear => PlanCodes.ProYear,
        ProLifetime => PlanCodes.ProLifetime,
        _ => null,
    };
}
