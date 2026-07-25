using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Workers;
using Microsoft.EntityFrameworkCore;

namespace CortexTerminal.Gateway.Membership;

public sealed class EntitlementService(
    IDbContextFactory<AppDbContext> dbFactory,
    IWorkerRegistry workers,
    ILogger<EntitlementService> logger)
    : IEntitlementService
{
    public async Task<Entitlement> GetEntitlementAsync(string userId, CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var user = await db.Users.FindAsync(new object?[] { userId }, ct);
        if (user is null)
            user = await db.Users.FirstOrDefaultAsync(u => u.Username == userId, ct);
        if (user is null)
            return FreeEntitlement(userId);

        var tier = user.MembershipTier;
        var expires = user.MembershipExpiresAtUtc;

        if (tier == MembershipTiers.Pro && expires is not null && expires <= DateTimeOffset.UtcNow)
        {
            tier = MembershipTiers.Free;
            user.MembershipTier = MembershipTiers.Free;
            user.MembershipPlanId = null;
            user.MembershipExpiresAtUtc = null;
            user.UpdatedAtUtc = DateTimeOffset.UtcNow;
            await MarkActiveSubscriptionExpiredAsync(db, userId, ct);
            await db.SaveChangesAsync(ct);
            logger.LogInformation("Membership lazily expired for user {UserId}", userId);
        }

        var plan = await ResolvePlanAsync(db, tier, user.MembershipPlanId, ct);
        return ToEntitlement(userId, tier, plan, tier == MembershipTiers.Pro ? expires : null);
    }

    public async Task EnforceWorkerQuotaAsync(string userId, CancellationToken ct)
    {
        var e = await GetEntitlementAsync(userId, ct);
        // Authoritative source is the registry's in-memory live-worker set, NOT the DB:
        // PostgresWorkerRegistry.Register persists fire-and-forget and the DB write may lag or
        // fail silently. Strict ownership (null-owner public workers don't count).
        var onlineCount = workers.CountOnlineWorkersForUser(userId);
        if (onlineCount >= e.MaxWorkers)
            throw new MembershipQuotaExceededException(
                $"Worker quota exceeded: {onlineCount}/{e.MaxWorkers}. Upgrade to Pro for more devices.",
                "worker_quota_exceeded");
    }

    private static async Task MarkActiveSubscriptionExpiredAsync(AppDbContext db, string userId, CancellationToken ct)
    {
        var active = await db.Subscriptions
            .Where(s => s.UserId == userId && s.Status == SubscriptionStatuses.Active)
            .ToListAsync(ct);
        foreach (var s in active)
        {
            s.Status = SubscriptionStatuses.Expired;
            s.UpdatedAtUtc = DateTimeOffset.UtcNow;
        }
    }

    private static async Task<Plan> ResolvePlanAsync(AppDbContext db, string tier, string? planId, CancellationToken ct)
    {
        if (!string.IsNullOrEmpty(planId))
        {
            var byId = await db.Plans.FindAsync(new object?[] { planId }, ct);
            if (byId is not null) return byId;
        }
        var code = tier == MembershipTiers.Pro ? PlanCodes.ProLifetime : PlanCodes.Free;
        return await db.Plans.SingleAsync(p => p.Code == code, ct);
    }

    private static Entitlement FreeEntitlement(string userId) => new(
        UserId: userId, Tier: MembershipTiers.Free, PlanCode: PlanCodes.Free,
        MaxWorkers: 0, MaxArtifactsPerSession: 0, MaxArtifactSizeBytes: 0,
        MaxArtifactAgeDays: 0, MaxScrollbackMegabytes: 0, ExpiresAtUtc: null);

    private static Entitlement ToEntitlement(string userId, string tier, Plan plan, DateTimeOffset? expires) => new(
        UserId: userId, Tier: tier, PlanCode: plan.Code,
        MaxWorkers: plan.MaxWorkers, MaxArtifactsPerSession: plan.MaxArtifactsPerSession,
        MaxArtifactSizeBytes: plan.MaxArtifactSizeBytes, MaxArtifactAgeDays: plan.MaxArtifactAgeDays,
        MaxScrollbackMegabytes: plan.MaxScrollbackMegabytes, ExpiresAtUtc: expires);
}
