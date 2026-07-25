using CortexTerminal.Gateway.Data;
using Microsoft.EntityFrameworkCore;

namespace CortexTerminal.Gateway.Membership;

public static class PlanCatalog
{
    public static async Task SeedAsync(AppDbContext db, MembershipOptions opts)
    {
        var existing = await db.Plans.ToDictionaryAsync(p => p.Code);
        Upsert(existing, db, PlanCodes.Free, MembershipTiers.Free, BillingPeriods.None,
            0m, opts.DefaultCurrency, opts.FreeMaxWorkers, opts.FreeMaxArtifactsPerSession,
            opts.FreeMaxArtifactSizeBytes, opts.FreeMaxArtifactAgeDays, opts.FreeMaxScrollbackMegabytes,
            sortOrder: 0);
        Upsert(existing, db, PlanCodes.ProMonth, MembershipTiers.Pro, BillingPeriods.Monthly,
            opts.ProMonthPrice, opts.DefaultCurrency, opts.ProMaxWorkers, opts.ProMaxArtifactsPerSession,
            opts.ProMaxArtifactSizeBytes, opts.ProMaxArtifactAgeDays, opts.ProMaxScrollbackMegabytes,
            sortOrder: 1);
        Upsert(existing, db, PlanCodes.ProYear, MembershipTiers.Pro, BillingPeriods.Yearly,
            opts.ProYearPrice, opts.DefaultCurrency, opts.ProMaxWorkers, opts.ProMaxArtifactsPerSession,
            opts.ProMaxArtifactSizeBytes, opts.ProMaxArtifactAgeDays, opts.ProMaxScrollbackMegabytes,
            sortOrder: 2);
        Upsert(existing, db, PlanCodes.ProLifetime, MembershipTiers.Pro, BillingPeriods.Lifetime,
            opts.ProLifetimePrice, opts.DefaultCurrency, opts.ProMaxWorkers, opts.ProMaxArtifactsPerSession,
            opts.ProMaxArtifactSizeBytes, opts.ProMaxArtifactAgeDays, opts.ProMaxScrollbackMegabytes,
            sortOrder: 3);
        await db.SaveChangesAsync();
    }

    private static void Upsert(
        Dictionary<string, Plan> existing, AppDbContext db,
        string code, string tier, string period,
        decimal price, string currency,
        int maxWorkers, int maxArtifacts, long maxSize, int maxAgeDays, int maxScrollbackMb,
        int sortOrder)
    {
        if (existing.TryGetValue(code, out var plan))
        {
            plan.Tier = tier;
            plan.BillingPeriod = period;
            plan.PriceAmount = price;
            plan.PriceCurrency = currency;
            plan.MaxWorkers = maxWorkers;
            plan.MaxArtifactsPerSession = maxArtifacts;
            plan.MaxArtifactSizeBytes = maxSize;
            plan.MaxArtifactAgeDays = maxAgeDays;
            plan.MaxScrollbackMegabytes = maxScrollbackMb;
            plan.SortOrder = sortOrder;
            plan.UpdatedAtUtc = DateTimeOffset.UtcNow;
            // IsActive intentionally preserved on update — admin may have deactivated a plan.
            return;
        }
        db.Plans.Add(new Plan
        {
            Code = code, Tier = tier, BillingPeriod = period,
            PriceAmount = price, PriceCurrency = currency,
            MaxWorkers = maxWorkers, MaxArtifactsPerSession = maxArtifacts,
            MaxArtifactSizeBytes = maxSize, MaxArtifactAgeDays = maxAgeDays,
            MaxScrollbackMegabytes = maxScrollbackMb,
            SortOrder = sortOrder, IsActive = true,
        });
    }
}
