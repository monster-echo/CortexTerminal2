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
            ?? await db.Users.FirstOrDefaultAsync(u => u.Username == userId, ct)
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

    public async Task<Subscription> RedeemAsync(string userId, string codeInput, CancellationToken ct)
    {
        var code = codeInput.Trim();
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var redeem = await db.RedeemCodes.FirstOrDefaultAsync(c => c.Code == code, ct);
        if (redeem is null || !redeem.IsActive)
            throw new RedeemCodeInvalidException("Redeem code not found.");
        if (redeem.ExpiresAtUtc is not null && redeem.ExpiresAtUtc <= DateTimeOffset.UtcNow)
            throw new RedeemCodeExpiredException("Redeem code has expired.");
        if (redeem.UsedCount >= redeem.MaxUses)
            throw new RedeemCodeExhaustedException("Redeem code is fully used.");
        var alreadyUsed = await db.RedeemCodeUsages.AnyAsync(u => u.RedeemCodeId == redeem.Id && u.UserId == userId, ct);
        if (alreadyUsed)
            throw new RedeemCodeAlreadyUsedException("You have already used this redeem code.");

        var plan = await db.Plans.FindAsync(new object?[] { redeem.PlanId }, ct)
            ?? throw new RedeemCodeInvalidException("Redeem code references an invalid plan.");
        var user = await db.Users.FindAsync(new object?[] { userId }, ct)
            ?? await db.Users.FirstOrDefaultAsync(u => u.Username == userId, ct)
            ?? throw new ArgumentException($"User not found: {userId}");

        var now = DateTimeOffset.UtcNow;
        var expiry = ComputeExpiry(redeem.BillingPeriod, now);

        var order = new MembershipOrder
        {
            UserId = userId, PlanId = plan.Id, BillingPeriod = redeem.BillingPeriod,
            Amount = 0m, Currency = plan.PriceCurrency,
            Channel = OrderChannels.Redeem, Status = OrderStatuses.Completed, CompletedAtUtc = now,
        };
        db.MembershipOrders.Add(order);

        var sub = new Subscription
        {
            UserId = userId, PlanId = plan.Id, Status = SubscriptionStatuses.Active,
            Period = redeem.BillingPeriod, StartAtUtc = now, ExpiresAtUtc = expiry,
            Source = SubscriptionSources.Redeem, SourceOrderId = order.Id, SourceRedeemCodeId = redeem.Id,
        };
        db.Subscriptions.Add(sub);

        db.RedeemCodeUsages.Add(new RedeemCodeUsage
        {
            RedeemCodeId = redeem.Id, UserId = userId, OrderId = order.Id, SubscriptionId = sub.Id,
        });
        redeem.UsedCount++;

        user.MembershipTier = plan.Tier;
        user.MembershipPlanId = plan.Id;
        user.MembershipExpiresAtUtc = expiry;
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
