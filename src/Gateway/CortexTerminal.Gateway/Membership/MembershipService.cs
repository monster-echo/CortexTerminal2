using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Membership.Iap;
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

    /// <summary>
    /// Idempotently grants a Pro subscription from a verified Apple in-app purchase
    /// transaction. A replay of the same <see cref="AppleVerifiedTransaction.OriginalTransactionId"/>
    /// returns the existing active subscription without creating a second order.
    /// </summary>
    public async Task<Subscription> GrantFromIapAsync(
        string userId, AppleVerifiedTransaction verified, string channel, CancellationToken ct)
    {
        var planCode = AppleProductIds.ToPlanCode(verified.ProductId)
            ?? throw new ArgumentException($"Unknown Apple product id: {verified.ProductId}");
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var plan = await db.Plans.FirstOrDefaultAsync(p => p.Code == planCode && p.IsActive, ct)
            ?? throw new ArgumentException($"Plan not found: {planCode}");

        // Idempotency: a verified replay of the same originalTransactionId must not double-grant.
        var source = SourceForChannel(channel);
        var existing = await db.Subscriptions.FirstOrDefaultAsync(
            s => s.Source == source && s.PlatformTransactionId == verified.OriginalTransactionId
                 && s.Status == SubscriptionStatuses.Active, ct);
        if (existing is not null) return existing;

        var now = DateTimeOffset.UtcNow;
        DateTimeOffset? expires = verified.ExpiresDateMs is long ms && ms > 0
            ? DateTimeOffset.FromUnixTimeMilliseconds(ms)
            : null;

        var order = new MembershipOrder
        {
            UserId = userId, PlanId = plan.Id, BillingPeriod = plan.BillingPeriod,
            Amount = plan.PriceAmount, Currency = plan.PriceCurrency,
            Channel = channel, Status = OrderStatuses.Completed, CompletedAtUtc = now,
            ProviderOrderId = verified.OriginalTransactionId,
        };
        db.MembershipOrders.Add(order);

        var sub = new Subscription
        {
            UserId = userId, PlanId = plan.Id, Status = SubscriptionStatuses.Active,
            Period = plan.BillingPeriod, StartAtUtc = now, ExpiresAtUtc = expires,
            Source = source, SourceOrderId = order.Id, PlatformTransactionId = verified.OriginalTransactionId,
        };
        db.Subscriptions.Add(sub);

        var user = await db.Users.FindAsync(new object?[] { userId }, ct)
            ?? await db.Users.FirstOrDefaultAsync(u => u.Username == userId, ct)
            ?? throw new ArgumentException($"User not found: {userId}");
        user.MembershipTier = plan.Tier;
        user.MembershipPlanId = plan.Id;
        user.MembershipExpiresAtUtc = expires;
        user.UpdatedAtUtc = now;

        await db.SaveChangesAsync(ct);
        return sub;
    }

    /// <summary>
    /// Extends the expiry of the existing active IAP subscription for
    /// <paramref name="verified.OriginalTransactionId"/> to the renewed transaction's expiry, and
    /// refreshes the user's Pro tier + expiry to match. Used by the webhook on a
    /// <c>DID_RENEW</c> / <c>SUBSCRIPTION_RENEWED</c> notification — a renewal extends a subscription
    /// in place, it does not create a new one (unlike <see cref="GrantFromIapAsync"/>, which
    /// short-circuits idempotently on an existing active subscription and would leave a stale expiry).
    /// Throws <see cref="ArgumentException"/> if no matching active subscription exists.
    /// </summary>
    public async Task<Subscription> ExtendFromIapRenewalAsync(
        string userId, AppleVerifiedTransaction verified, CancellationToken ct)
    {
        var source = SourceForChannel(OrderChannels.IapApple);
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var sub = await db.Subscriptions.FirstOrDefaultAsync(
            s => s.Source == source && s.PlatformTransactionId == verified.OriginalTransactionId
                 && s.Status == SubscriptionStatuses.Active, ct)
            ?? throw new ArgumentException(
                $"No active Apple subscription to renew for originalTransactionId: {verified.OriginalTransactionId}");

        DateTimeOffset? expires = verified.ExpiresDateMs is long ms && ms > 0
            ? DateTimeOffset.FromUnixTimeMilliseconds(ms)
            : null;

        var now = DateTimeOffset.UtcNow;
        sub.ExpiresAtUtc = expires;
        sub.UpdatedAtUtc = now;

        var user = await db.Users.FindAsync(new object?[] { userId }, ct)
            ?? await db.Users.FirstOrDefaultAsync(u => u.Username == userId, ct)
            ?? throw new ArgumentException($"User not found: {userId}");
        user.MembershipTier = MembershipTiers.Pro;
        user.MembershipExpiresAtUtc = expires;
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
