using CortexTerminal.Gateway.Audit;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Membership;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Storage;
using CortexTerminal.Gateway.Workers;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using NSubstitute;

namespace CortexTerminal.Gateway.Tests;

internal static class TestSessionFactory
{
    private static IDbContextFactory<AppDbContext> CreateContextFactory()
    {
        var dbName = $"test-{Guid.NewGuid():N}";
        var services = new ServiceCollection();
        services.AddDbContextFactory<AppDbContext>(options =>
            options.UseInMemoryDatabase(dbName));
        return services.BuildServiceProvider().GetRequiredService<IDbContextFactory<AppDbContext>>();
    }

    public static IDbContextFactory<AppDbContext> CreateContextFactoryPublic() => CreateContextFactory();

    public static PostgresWorkerRegistry CreateWorkerRegistry()
        => new(
            CreateContextFactory(),
            LoggerFactory.Create(_ => { }).CreateLogger<PostgresWorkerRegistry>());

    public static PostgresSessionCoordinator CreateCoordinator(IWorkerRegistry workers, TimeProvider? timeProvider = null)
        => new(
            workers,
            CreateContextFactory(),
            LoggerFactory.Create(_ => { }).CreateLogger<PostgresSessionCoordinator>(),
            timeProvider);

    public static UserPreferenceService CreatePreferenceService()
        => new(CreateContextFactory());

    public static (IDbContextFactory<AppDbContext> db, PostgresSessionCoordinator sessions, ArtifactService artifacts) CreateArtifactService(
        IWorkerRegistry workers,
        IArtifactStorage storage,
        IHubContext<TerminalHub> terminalHub,
        IArtifactCommandDispatcher workerCommands,
        TimeProvider? timeProvider = null,
        ArtifactStorageOptions? options = null,
        IAuditLogStore? auditLog = null,
        IEntitlementService? entitlements = null)
    {
        var factory = CreateContextFactory();
        var loggerFactory = LoggerFactory.Create(_ => { });
        var sessions = new PostgresSessionCoordinator(
            workers,
            factory,
            loggerFactory.CreateLogger<PostgresSessionCoordinator>(),
            timeProvider);
        var opts = options ?? new ArtifactStorageOptions();
        // Legacy artifact tests assert against the ArtifactStorageOptions.MaxArtifactsPerSession
        // cap. Mirror that via a substituted entitlement so they stay green without per-test setup.
        // Tests exercising the real per-tier lookup pass their own IEntitlementService.
        var entitlement = entitlements ?? CreateLegacyEntitlement(opts);
        var artifacts = new ArtifactService(
            factory,
            storage,
            sessions,
            auditLog ?? new NullAuditLogStore(),
            terminalHub,
            workerCommands,
            Options.Create(opts),
            loggerFactory.CreateLogger<ArtifactService>(),
            entitlement);
        return (factory, sessions, artifacts);
    }

    private static IEntitlementService CreateLegacyEntitlement(ArtifactStorageOptions opts)
    {
        var sub = NSubstitute.Substitute.For<IEntitlementService>();
        sub.GetEntitlementAsync(Arg.Any<string>(), Arg.Any<CancellationToken>())
            .Returns(new Entitlement(
                UserId: "legacy",
                Tier: MembershipTiers.Free,
                PlanCode: PlanCodes.Free,
                MaxWorkers: opts.MaxArtifactsPerSession > 0 ? 1 : 0,
                MaxArtifactsPerSession: opts.MaxArtifactsPerSession,
                MaxArtifactSizeBytes: opts.MaxArtifactSizeBytes,
                MaxArtifactAgeDays: opts.MaxArtifactAgeDays,
                MaxScrollbackMegabytes: 0,
                ExpiresAtUtc: null));
        return sub;
    }

    public static AgentActivityService CreateAgentActivityService(IHubContext<TerminalHub> terminalHub)
    {
        var factory = CreateContextFactory();
        var loggerFactory = LoggerFactory.Create(_ => { });
        return new AgentActivityService(
            factory,
            terminalHub,
            loggerFactory.CreateLogger<AgentActivityService>());
    }
}
