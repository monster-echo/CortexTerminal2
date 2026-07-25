using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Audit;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Membership;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Storage;
using CortexTerminal.Gateway.Tests.Sessions.Fakes;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class ArtifactQuotaGateTests
{
    private static async Task<(IDbContextFactory<AppDbContext> db, ArtifactService artifacts, string sessionId, string userId)> SetupAsync(string tier)
    {
        var factory = TestSessionFactory.CreateContextFactoryPublic();
        await using (var seed = await factory.CreateDbContextAsync())
        {
            await PlanCatalog.SeedAsync(seed, new MembershipOptions());
        }

        var userId = Guid.NewGuid().ToString("N");
        await using (var seed = await factory.CreateDbContextAsync())
        {
            seed.Users.Add(new User
            {
                Id = userId,
                Username = $"u-{userId.Substring(0, 8)}",
                Role = "user",
                Status = "active",
                MembershipTier = tier,
                CreatedAtUtc = DateTimeOffset.UtcNow,
                UpdatedAtUtc = DateTimeOffset.UtcNow,
            });
            await seed.SaveChangesAsync();
        }

        var entitlements = new EntitlementService(factory, NullLogger<EntitlementService>.Instance);
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1", ownerUserId: userId);
        var sessions = TestSessionFactory.CreateCoordinator(workers);
        var create = await sessions.CreateSessionAsync(userId, new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);

        var artifacts = new ArtifactService(
            factory,
            new FakeArtifactStorage(),
            sessions,
            new NullAuditLogStore(),
            new ArtifactTestHubContext(userId),
            new RecordingArtifactCommandDispatcher(),
            Options.Create(new ArtifactStorageOptions { MaxArtifactSizeBytes = 50 * 1024 * 1024 }),
            NullLogger<ArtifactService>.Instance,
            entitlements);
        return (factory, artifacts, create.Response!.SessionId, userId);
    }

    private static async Task SeedArtifactsAsync(IDbContextFactory<AppDbContext> factory, string sessionId, string userId, int count)
    {
        for (var i = 0; i < count; i++)
        {
            await using var ctx = await factory.CreateDbContextAsync();
            ctx.Artifacts.Add(new ArtifactEntity
            {
                Id = Guid.NewGuid().ToString("N"),
                SessionId = sessionId,
                Filename = $"seed-{i}.txt",
                SizeBytes = 1,
                Status = ArtifactStatus.Pending,
                Origin = ArtifactOrigin.Console,
                OwnerUserId = userId,
                FileCategory = ArtifactFileCategory.Text,
                CreatedAtUtc = DateTimeOffset.UtcNow,
                ExpiresAtUtc = DateTimeOffset.UtcNow.AddDays(1),
            });
            await ctx.SaveChangesAsync();
        }
    }

    private static async Task<int> ReadQuotaAsync(IDbContextFactory<AppDbContext> factory, string planCode)
    {
        await using var ctx = await factory.CreateDbContextAsync();
        var plan = await ctx.Plans.SingleAsync(p => p.Code == planCode);
        return plan.MaxArtifactsPerSession;
    }

    [Fact]
    public async Task CreateForConsoleUploadAsync_FreeUserOverQuota_Throws()
    {
        var (db, artifacts, sessionId, userId) = await SetupAsync(MembershipTiers.Free);
        var freeQuota = await ReadQuotaAsync(db, PlanCodes.Free);
        await SeedArtifactsAsync(db, sessionId, userId, freeQuota);

        var request = new CreateArtifactRequest(sessionId, "overflow.txt", 1, null, ArtifactOrigin.Console);
        var act = () => artifacts.CreateForConsoleUploadAsync(userId, request, CancellationToken.None);

        var thrown = (await act.Should().ThrowAsync<MembershipQuotaExceededException>())
            .Subject.Single();
        thrown.ErrorCode.Should().Be("artifact_quota_exceeded");
        thrown.Message.Should().Contain("Artifact quota exceeded: 100/100");
        thrown.Message.Should().Contain("plan free");
    }

    [Fact]
    public async Task CreateForConsoleUploadAsync_FreeUserUnderQuota_AllowsUpload()
    {
        var (_, artifacts, sessionId, userId) = await SetupAsync(MembershipTiers.Free);
        var request = new CreateArtifactRequest(sessionId, "first.txt", 1, null, ArtifactOrigin.Console);

        var resp = await artifacts.CreateForConsoleUploadAsync(userId, request, CancellationToken.None);

        resp.ArtifactId.Should().NotBeEmpty();
    }

    [Fact]
    public async Task CreateForConsoleUploadAsync_ProUser_HasHigherQuota()
    {
        var (db, artifacts, sessionId, userId) = await SetupAsync(MembershipTiers.Pro);
        var freeQuota = await ReadQuotaAsync(db, PlanCodes.Free);
        var proQuota = await ReadQuotaAsync(db, PlanCodes.ProYear);
        proQuota.Should().BeGreaterThan(freeQuota);

        // Seed exactly the Free quota — would overflow Free but fit Pro.
        await SeedArtifactsAsync(db, sessionId, userId, freeQuota);

        var request = new CreateArtifactRequest(sessionId, "next.txt", 1, null, ArtifactOrigin.Console);
        var resp = await artifacts.CreateForConsoleUploadAsync(userId, request, CancellationToken.None);

        resp.ArtifactId.Should().NotBeEmpty();
    }
}
