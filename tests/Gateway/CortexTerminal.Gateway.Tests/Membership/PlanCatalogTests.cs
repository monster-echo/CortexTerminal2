using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Membership;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class PlanCatalogTests
{
    [Fact]
    public async Task SeedAsync_CreatesFourPlans_WhenEmpty()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase($"catalog_{Guid.NewGuid():N}").Options;
        await using var db = new AppDbContext(options);

        await PlanCatalog.SeedAsync(db, new MembershipOptions());

        var codes = await db.Plans.Select(p => p.Code).ToListAsync();
        codes.Should().BeEquivalentTo(new[] { "free", "pro_month", "pro_year", "pro_lifetime" });
    }

    [Fact]
    public async Task SeedAsync_IsIdempotent()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase($"catalog_{Guid.NewGuid():N}").Options;
        await using var db = new AppDbContext(options);

        await PlanCatalog.SeedAsync(db, new MembershipOptions());
        await PlanCatalog.SeedAsync(db, new MembershipOptions());

        db.Plans.Should().HaveCount(4);
    }

    [Fact]
    public async Task SeedAsync_ProPlansHaveHigherWorkerQuotaThanFree()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase($"catalog_{Guid.NewGuid():N}").Options;
        await using var db = new AppDbContext(options);
        await PlanCatalog.SeedAsync(db, new MembershipOptions());

        var free = await db.Plans.SingleAsync(p => p.Code == PlanCodes.Free);
        var pro = await db.Plans.SingleAsync(p => p.Code == PlanCodes.ProMonth);
        pro.MaxWorkers.Should().BeGreaterThan(free.MaxWorkers);
    }
}
