using CortexTerminal.Gateway.Audit;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Storage;
using CortexTerminal.Gateway.Workers;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

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
        IAuditLogStore? auditLog = null)
    {
        var factory = CreateContextFactory();
        var loggerFactory = LoggerFactory.Create(_ => { });
        var sessions = new PostgresSessionCoordinator(
            workers,
            factory,
            loggerFactory.CreateLogger<PostgresSessionCoordinator>(),
            timeProvider);
        var artifacts = new ArtifactService(
            factory,
            storage,
            sessions,
            auditLog ?? new NullAuditLogStore(),
            terminalHub,
            workerCommands,
            Options.Create(options ?? new ArtifactStorageOptions()),
            loggerFactory.CreateLogger<ArtifactService>());
        return (factory, sessions, artifacts);
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
