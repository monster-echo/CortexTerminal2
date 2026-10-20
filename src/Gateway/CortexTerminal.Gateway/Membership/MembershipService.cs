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
        var newExpiry = ComputeExpiry(redeem.BillingPeriod, now);

        // 已有不短于新兑换期限的 Pro 会员（含终身）时不消耗兑换码：
        // 否则下面的覆盖会把 user.MembershipExpiresAtUtc 改短，终身会员会在到期后被惰性降级。
        if (user.MembershipTier == MembershipTiers.Pro &&
            (user.MembershipExpiresAtUtc is null || user.MembershipExpiresAtUtc > newExpiry))
            throw new RedeemCodeInvalidException(
                "You already hold an active Pro membership; the code was not consumed.");

        var expiry = newExpiry;

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
        var now = DateTimeOffset.UtcNow;
        DateTimeOffset? expires = verified.ExpiresDateMs is long ms && ms > 0 ? DateTimeOffset.FromUnixTimeMilliseconds(ms) : null;
        if (verified.RevocationDateMs is > 0 || (planCode != PlanCodes.ProLifetime && (expires is null || expires <= now)))
            throw new ArgumentException("Apple purchase is revoked or expired.");
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        await using var transaction = db.Database.IsNpgsql() ? await db.Database.BeginTransactionAsync(ct) : null;
        if (transaction is not null)
        {
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({verified.OriginalTransactionId}, 0))", ct);
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({userId}, 1))", ct);
        }
        var plan = await db.Plans.FirstOrDefaultAsync(p => p.Code == planCode && p.IsActive, ct)
            ?? throw new ArgumentException($"Plan not found: {planCode}");
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId || u.Username == userId, ct)
            ?? throw new ArgumentException($"User not found: {userId}");
        var source = SourceForChannel(channel);
        var sub = await db.Subscriptions.FirstOrDefaultAsync(s => s.Source == source
            && s.PlatformTransactionId == verified.OriginalTransactionId, ct);
        if (sub is not null && sub.UserId != userId) throw new ArgumentException("This purchase is already linked to another account.");
        if (sub?.Status == SubscriptionStatuses.Revoked) throw new ArgumentException("This Apple purchase has been revoked.");
        var orderId = verified.TransactionId ?? verified.OriginalTransactionId;
        var order = await db.MembershipOrders.FirstOrDefaultAsync(o => o.Channel == channel && o.ProviderOrderId == orderId, ct);
        if (order is not null && order.UserId != userId) throw new ArgumentException("This order is already linked to another account.");
        if (order is null)
        {
            order = new MembershipOrder {
                UserId = userId, PlanId = plan.Id, BillingPeriod = plan.BillingPeriod,
                Amount = plan.PriceAmount, Currency = plan.PriceCurrency, Channel = channel,
                Status = OrderStatuses.Completed, CompletedAtUtc = now, ProviderOrderId = orderId,
            };
            db.MembershipOrders.Add(order);
        }
        if (sub is null)
        {
            sub = new Subscription {
                UserId = userId, PlanId = plan.Id, Period = plan.BillingPeriod,
                Status = SubscriptionStatuses.Active, StartAtUtc = now, ExpiresAtUtc = expires,
                Source = source, SourceOrderId = order.Id, PlatformTransactionId = verified.OriginalTransactionId,
            };
            db.Subscriptions.Add(sub);
        }
        else if (expires is null || sub.ExpiresAtUtc is null || expires >= sub.ExpiresAtUtc)
        {
            sub.PlanId = plan.Id; sub.Period = plan.BillingPeriod;
            sub.Status = SubscriptionStatuses.Active; sub.ExpiresAtUtc = expires;
            sub.SourceOrderId = order.Id; sub.UpdatedAtUtc = now;
        }
        await db.SaveChangesAsync(ct);
        await RefreshEffectiveEntitlementAsync(db, user, userId, ct);
        await db.SaveChangesAsync(ct);
        if (transaction is not null) await transaction.CommitAsync(ct);
        return sub;
    }

    /// <summary>
    /// Applies a server-verified Huawei purchase to the same membership catalog and entitlement
    /// state used by Apple, redeem codes, and manual grants. The stable Huawei purchase token is
    /// the subscription idempotency key; new renewal order IDs create order history rows while
    /// updating the existing subscription expiry.
    /// </summary>
    public async Task<Subscription> GrantFromHuaweiIapAsync(
        string userId, HuaweiVerifiedTransaction verified, string planCode, CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var plan = await db.Plans.FirstOrDefaultAsync(p => p.Code == planCode && p.IsActive, ct)
            ?? throw new ArgumentException($"Plan not found: {planCode}");
        var user = await db.Users.FindAsync(new object?[] { userId }, ct)
            ?? await db.Users.FirstOrDefaultAsync(u => u.Username == userId, ct)
            ?? throw new ArgumentException($"User not found: {userId}");

        var source = SubscriptionSources.IapHuawei;
        var existing = await db.Subscriptions.FirstOrDefaultAsync(
            s => s.Source == source && s.PlatformTransactionId == verified.PurchaseToken, ct);
        if (existing is not null && existing.UserId != userId)
            throw new ArgumentException("This Huawei purchase is already linked to another Corterm account.");

        DateTimeOffset? expires = verified.ExpiresDateMs is long ms && ms > 0
            ? DateTimeOffset.FromUnixTimeMilliseconds(ms)
            : null;
        var now = DateTimeOffset.UtcNow;

        // A subscription purchase token remains stable across renewals. Keep one subscription
        // row, but preserve each distinct Huawei order in MembershipOrders.
        var order = await db.MembershipOrders.FirstOrDefaultAsync(
            o => o.Channel == OrderChannels.IapHuawei && o.ProviderOrderId == verified.PurchaseOrderId, ct);
        if (order is not null && order.UserId != userId)
            throw new ArgumentException("This Huawei order is already linked to another Corterm account.");
        if (order is null)
        {
            order = new MembershipOrder
            {
                UserId = userId, PlanId = plan.Id, BillingPeriod = plan.BillingPeriod,
                Amount = plan.PriceAmount, Currency = plan.PriceCurrency,
                Channel = OrderChannels.IapHuawei, Status = OrderStatuses.Completed,
                CompletedAtUtc = now, ProviderOrderId = verified.PurchaseOrderId,
            };
            db.MembershipOrders.Add(order);
        }

        if (existing is null)
        {
            existing = new Subscription
            {
                UserId = userId, PlanId = plan.Id, Status = SubscriptionStatuses.Active,
                Period = plan.BillingPeriod, StartAtUtc = now, ExpiresAtUtc = expires,
                Source = source, SourceOrderId = order.Id,
                PlatformTransactionId = verified.PurchaseToken,
            };
            db.Subscriptions.Add(existing);
        }
        else
        {
            existing.PlanId = plan.Id;
            existing.Period = plan.BillingPeriod;
            existing.Status = SubscriptionStatuses.Active;
            existing.ExpiresAtUtc = expires;
            existing.SourceOrderId = order.Id;
            existing.UpdatedAtUtc = now;
        }

        user.MembershipTier = plan.Tier;
        user.MembershipPlanId = plan.Id;
        user.MembershipExpiresAtUtc = plan.BillingPeriod == BillingPeriods.Lifetime ? null : expires;
        user.UpdatedAtUtc = now;
        await db.SaveChangesAsync(ct);
        return existing;
    }

    /// <summary>
    /// 华为订阅服务端通知（续订 / 过期 / 取消）的状态机：按 purchaseToken 找到既有订阅，
    /// 依据华为服务器校验结果推进 Active/Expired，并刷新用户有效会员（RefreshEffectiveEntitlementAsync）。
    /// 返回 false 表示本网关没有该 token 对应的订阅（如购买发生在客户端验证路径之外），调用方应 200 忽略。
    /// </summary>
    public async Task<bool> ApplyHuaweiSubscriptionStateAsync(HuaweiVerifiedTransaction verified, CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var sub = await db.Subscriptions.FirstOrDefaultAsync(
            s => s.Source == SubscriptionSources.IapHuawei && s.PlatformTransactionId == verified.PurchaseToken, ct);
        if (sub is null) return false;
        var user = await db.Users.FindAsync(new object?[] { sub.UserId }, ct)
            ?? await db.Users.FirstOrDefaultAsync(u => u.Username == sub.UserId, ct)
            ?? throw new ArgumentException($"User not found: {sub.UserId}");

        var now = DateTimeOffset.UtcNow;
        DateTimeOffset? expires = null;
        if (verified.ExpiresDateMs is long ms && ms > 0)
            expires = DateTimeOffset.FromUnixTimeMilliseconds(ms);
        var active = verified.PurchaseState == 0
            && (verified.IsSubscriptionValid ?? true)
            && (expires is null || expires > now);

        sub.Status = active ? SubscriptionStatuses.Active : SubscriptionStatuses.Expired;
        if (expires is not null) sub.ExpiresAtUtc = expires;
        sub.UpdatedAtUtc = now;

        await RefreshEffectiveEntitlementAsync(db, user, sub.UserId, ct);
        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<Subscription> GrantFromGoogleIapAsync(
        string userId, GoogleVerifiedPurchase verified, string planCode, CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        // PostgreSQL transaction-scoped locks serialize replayed tokens and concurrent
        // purchases for this account across Gateway instances; no raw token is stored.
        await using var transaction = db.Database.IsNpgsql() ? await db.Database.BeginTransactionAsync(ct) : null;
        if (transaction is not null)
        {
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({verified.Token}, 0))", ct);
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({userId}, 1))", ct);
        }
        if (!verified.Active) throw new ArgumentException("Cannot grant an inactive Google purchase.");
        var plan = await db.Plans.FirstOrDefaultAsync(p => p.Code == planCode && p.IsActive, ct)
            ?? throw new ArgumentException($"Plan not found: {planCode}");
        var user = await db.Users.FindAsync(new object?[] { userId }, ct)
            ?? await db.Users.FirstOrDefaultAsync(u => u.Username == userId, ct)
            ?? throw new ArgumentException($"User not found: {userId}");

        var source = SubscriptionSources.IapGoogle;
        var existing = await db.Subscriptions.FirstOrDefaultAsync(
            s => s.Source == source && s.PlatformTransactionId == verified.Token, ct);
        if (existing is not null && existing.UserId != userId)
            throw new ArgumentException("This Google purchase is already linked to another Corterm account.");

        DateTimeOffset? expires = verified.ExpiresMs is long ms && ms > 0
            ? DateTimeOffset.FromUnixTimeMilliseconds(ms)
            : null;
        var now = DateTimeOffset.UtcNow;

        // A subscription purchase token remains stable across renewals. Keep one subscription
        // row, but preserve each distinct Google order in MembershipOrders.
        var order = await db.MembershipOrders.FirstOrDefaultAsync(
            o => o.Channel == OrderChannels.IapGoogle && o.ProviderOrderId == verified.OrderId, ct);
        if (order is not null && order.UserId != userId)
            throw new ArgumentException("This Google order is already linked to another Corterm account.");
        if (order is null)
        {
            order = new MembershipOrder
            {
                UserId = userId, PlanId = plan.Id, BillingPeriod = plan.BillingPeriod,
                Amount = plan.PriceAmount, Currency = plan.PriceCurrency,
                Channel = OrderChannels.IapGoogle, Status = OrderStatuses.Completed,
                CompletedAtUtc = now, ProviderOrderId = verified.OrderId,
            };
            db.MembershipOrders.Add(order);
        }

        if (existing is null)
        {
            existing = new Subscription
            {
                UserId = userId, PlanId = plan.Id, Status = SubscriptionStatuses.Active,
                Period = plan.BillingPeriod, StartAtUtc = now, ExpiresAtUtc = expires,
                Source = source, SourceOrderId = order.Id,
                PlatformTransactionId = verified.Token,
            };
            db.Subscriptions.Add(existing);
        }
        else
        {
            existing.PlanId = plan.Id;
            existing.Period = plan.BillingPeriod;
            existing.Status = SubscriptionStatuses.Active;
            existing.ExpiresAtUtc = expires;
            existing.SourceOrderId = order.Id;
            existing.UpdatedAtUtc = now;
        }

        await db.SaveChangesAsync(ct);
        await RefreshEffectiveEntitlementAsync(db, user, userId, ct);
        await db.SaveChangesAsync(ct);
        if (transaction is not null) await transaction.CommitAsync(ct);
        return existing;
    }

    public async Task RevokeGoogleIapAsync(string userId, string tokenKey, CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        await using var transaction = db.Database.IsNpgsql() ? await db.Database.BeginTransactionAsync(ct) : null;
        if (transaction is not null)
        {
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({tokenKey}, 0))", ct);
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({userId}, 1))", ct);
        }
        var subscription = await db.Subscriptions.FirstOrDefaultAsync(s =>
            s.Source == SubscriptionSources.IapGoogle && s.PlatformTransactionId == tokenKey && s.UserId == userId, ct);
        if (subscription is null) return;
        subscription.Status = SubscriptionStatuses.Revoked;
        subscription.UpdatedAtUtc = DateTimeOffset.UtcNow;
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId || u.Username == userId, ct);
        await db.SaveChangesAsync(ct);
        if (user is not null)
        {
            await RefreshEffectiveEntitlementAsync(db, user, userId, ct);
            await db.SaveChangesAsync(ct);
        }
        if (transaction is not null) await transaction.CommitAsync(ct);
    }

    internal static async Task RefreshEffectiveEntitlementAsync(AppDbContext db, User user, string userId, CancellationToken ct)
    {
        var now = DateTimeOffset.UtcNow;
        var candidates = await (from sub in db.Subscriptions
            join plan in db.Plans on sub.PlanId equals plan.Id
            where (sub.UserId == userId || sub.UserId == user.Id) && sub.Status == SubscriptionStatuses.Active
                && (sub.ExpiresAtUtc == null || sub.ExpiresAtUtc > now) && plan.Tier == MembershipTiers.Pro
            select new { sub.PlanId, sub.ExpiresAtUtc }).ToListAsync(ct);
        var best = candidates.OrderByDescending(s => s.ExpiresAtUtc == null)
            .ThenByDescending(s => s.ExpiresAtUtc).FirstOrDefault();
        user.MembershipTier = best is null ? MembershipTiers.Free : MembershipTiers.Pro;
        user.MembershipPlanId = best?.PlanId;
        user.MembershipExpiresAtUtc = best?.ExpiresAtUtc;
        user.UpdatedAtUtc = now;
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
    public Task<Subscription> ExtendFromIapRenewalAsync(
        string userId, AppleVerifiedTransaction verified, CancellationToken ct)
        => GrantFromIapAsync(userId, verified, OrderChannels.IapApple, ct);

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
