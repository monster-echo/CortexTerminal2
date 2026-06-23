using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

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
}
