using CortexTerminal.Gateway.Data;
using Microsoft.EntityFrameworkCore;

namespace CortexTerminal.Gateway.Membership;

public sealed class MembershipService(IDbContextFactory<AppDbContext> dbFactory)
{
    public async Task<Subscription> GrantAsync(
        string userId, string planId, string channel,
        DateTimeOffset? expiresAtUtc, string grantedByUserId,
        string? sourceRedeemCodeId, CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var plan = await db.Plans.FindAsync(new object?[] { planId }, ct)
            ?? throw new ArgumentException($"Plan not found: {planId}");
        var user = await db.Users.FindAsync(new object?[] { userId }, ct)
            ?? throw new ArgumentException($"User not found: {userId}");

        var now = DateTimeOffset.UtcNow;
        var effectiveExpiry = expiresAtUtc ?? ComputeExpiry(plan.BillingPeriod, now);

        var order = new MembershipOrder
        {
            UserId = userId, PlanId = plan.Id, BillingPeriod = plan.BillingPeriod,
            Amount = plan.PriceAmount, Currency = plan.PriceCurrency,
            Channel = channel, Status = OrderStatuses.Completed, CompletedAtUtc = now,
        };
        db.MembershipOrders.Add(order);

        var sub = new Subscription
        {
            UserId = userId, PlanId = plan.Id,
            Status = SubscriptionStatuses.Active, Period = plan.BillingPeriod,
            StartAtUtc = now, ExpiresAtUtc = effectiveExpiry,
            Source = SourceForChannel(channel), SourceOrderId = order.Id,
            SourceRedeemCodeId = sourceRedeemCodeId,
        };
        db.Subscriptions.Add(sub);

        user.MembershipTier = plan.Tier;
        user.MembershipPlanId = plan.Id;
        user.MembershipExpiresAtUtc = effectiveExpiry;
        user.UpdatedAtUtc = now;

        await db.SaveChangesAsync(ct);
        return sub;
    }

    internal static DateTimeOffset? ComputeExpiry(string billingPeriod, DateTimeOffset now) => billingPeriod switch
    {
        BillingPeriods.Monthly => now.AddMonths(1),
        BillingPeriods.Yearly => now.AddYears(1),
        BillingPeriods.Lifetime => null,
        _ => null,
    };

    internal static string SourceForChannel(string channel) => channel switch
    {
        OrderChannels.Manual => SubscriptionSources.ManualGrant,
        OrderChannels.Redeem => SubscriptionSources.Redeem,
        OrderChannels.IapApple => SubscriptionSources.IapApple,
        OrderChannels.IapGoogle => SubscriptionSources.IapGoogle,
        OrderChannels.IapHuawei => SubscriptionSources.IapHuawei,
        _ => SubscriptionSources.ManualGrant,
    };
}
