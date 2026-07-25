using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Membership;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Membership;

/// <summary>
/// Tests the worker-quota gate (T9). Uses a REAL PostgresWorkerRegistry (in-memory factory)
/// so the strict in-memory count path is exercised end-to-end, and a real EntitlementService
/// so the per-tier plan lookup is the one production uses.
/// </summary>
public sealed class WorkerQuotaGateTests
{
    private static async Task<(EntitlementService svc, PostgresWorkerRegistry registry, AppDbContext db, string userId)>
        SetupAsync(string tier, string? planId = null, DateTimeOffset? expires = null)
    {
        var factory = TestSessionFactory.CreateContextFactoryPublic();
        var db = await factory.CreateDbContextAsync();
        await PlanCatalog.SeedAsync(db, new MembershipOptions());

        var userId = Guid.NewGuid().ToString("N");
        db.Users.Add(new User
        {
            Id = userId,
            Username = $"u-{userId.Substring(0, 8)}",
            Role = "user",
            Status = "active",
            MembershipTier = tier,
            MembershipPlanId = planId,
            MembershipExpiresAtUtc = expires,
            CreatedAtUtc = DateTimeOffset.UtcNow,
            UpdatedAtUtc = DateTimeOffset.UtcNow,
        });
        await db.SaveChangesAsync();

        var registry = TestSessionFactory.CreateWorkerRegistry();
        var svc = new EntitlementService(factory, registry, NullLogger<EntitlementService>.Instance);
        return (svc, registry, db, userId);
    }

    private static async Task<int> ReadMaxWorkersAsync(AppDbContext db, string planCode)
    {
        var plan = await db.Plans.SingleAsync(p => p.Code == planCode);
        return plan.MaxWorkers;
    }

    [Fact]
    public async Task EnforceWorkerQuotaAsync_FreeUserAtLimit_Throws()
    {
        var (svc, registry, db, userId) = await SetupAsync(MembershipTiers.Free);
        var freeMax = await ReadMaxWorkersAsync(db, PlanCodes.Free);
        freeMax.Should().BeGreaterThan(0, "Free plan must allow at least one worker");

        // Register exactly Free.MaxWorkers online workers for this owner — the next attempt must
        // be denied. Use distinct worker IDs so each Register call creates a new entry.
        for (var i = 0; i < freeMax; i++)
            registry.Register($"worker-{i}", $"conn-{i}", ownerUserId: userId);

        var act = () => svc.EnforceWorkerQuotaAsync(userId, CancellationToken.None);

        var thrown = (await act.Should().ThrowAsync<MembershipQuotaExceededException>())
            .Subject.Single();
        thrown.ErrorCode.Should().Be("worker_quota_exceeded");
        thrown.Message.Should().Contain($"Worker quota exceeded: {freeMax}/{freeMax}");
    }

    [Fact]
    public async Task EnforceWorkerQuotaAsync_ProUserUnderLimit_Ok()
    {
        var proYear = await FindPlanCodeAsync(PlanCodes.ProYear);
        var (svc, registry, db, userId) = await SetupAsync(MembershipTiers.Pro, planId: proYear.Id, expires: DateTimeOffset.UtcNow.AddDays(30));
        var proMax = await ReadMaxWorkersAsync(db, PlanCodes.ProYear);
        proMax.Should().BeGreaterThan(0);

        // Register one FEWER than the Pro quota — must NOT throw.
        for (var i = 0; i < proMax - 1; i++)
            registry.Register($"pro-worker-{i}", $"pro-conn-{i}", ownerUserId: userId);

        var act = () => svc.EnforceWorkerQuotaAsync(userId, CancellationToken.None);

        await act.Should().NotThrowAsync();
    }

    /// <summary>
    /// Regression for I-2: a worker owned by a DIFFERENT user (or a legacy null-owner public
    /// worker) must NOT count toward the target user's quota. The count must be strict
    /// (OwnerUserId == userId && IsOnline), never the null-owner-permissive branch used by
    /// GetOnlineWorkersForUser.
    /// </summary>
    [Fact]
    public async Task EnforceWorkerQuotaAsync_StrictOwnership_DoesNotCountOthersWorkers()
    {
        var (svc, registry, db, userId) = await SetupAsync(MembershipTiers.Free);
        var freeMax = await ReadMaxWorkersAsync(db, PlanCodes.Free);

        // Saturate the registry with workers owned by someone else AND a null-owner public
        // worker. None of these belong to `userId`, so the gate must still pass even though
        // the registry is full of online workers.
        var otherUser = $"other-{Guid.NewGuid():N}";
        for (var i = 0; i < freeMax + 5; i++)
            registry.Register($"other-worker-{i}", $"other-conn-{i}", ownerUserId: otherUser);
        // Legacy open-access worker (null owner) — GetOnlineWorkersForUser would count this.
        registry.Register("public-worker", "public-conn", ownerUserId: null);

        // `userId` has zero workers of their own — must NOT throw.
        var act = () => svc.EnforceWorkerQuotaAsync(userId, CancellationToken.None);
        await act.Should().NotThrowAsync();

        // And the strict count must be zero for userId despite the registry being non-empty.
        registry.CountOnlineWorkersForUser(userId).Should().Be(0);
        // Sanity: the permissive accessor WOULD have counted the public worker (confirms the
        // trap the strict method exists to avoid).
        registry.GetOnlineWorkersForUser(userId).Should().ContainSingle(w => w.WorkerId == "public-worker");
    }

    private static async Task<Plan> FindPlanCodeAsync(string code)
    {
        var factory = TestSessionFactory.CreateContextFactoryPublic();
        await using var db = await factory.CreateDbContextAsync();
        await PlanCatalog.SeedAsync(db, new MembershipOptions());
        return await db.Plans.SingleAsync(p => p.Code == code);
    }
}
