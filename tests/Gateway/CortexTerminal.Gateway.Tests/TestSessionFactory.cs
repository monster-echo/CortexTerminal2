using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Gateway.Tests;

internal static class TestSessionFactory
{
    public static IServiceScopeFactory CreateScopeFactory()
    {
        var services = new ServiceCollection();
        services.AddDbContext<AppDbContext>(options =>
            options.UseInMemoryDatabase($"test-{Guid.NewGuid():N}"));
        return services.BuildServiceProvider().GetRequiredService<IServiceScopeFactory>();
    }

    public static PostgresWorkerRegistry CreateWorkerRegistry()
    {
        return new PostgresWorkerRegistry(
            CreateScopeFactory(),
            LoggerFactory.Create(_ => { }).CreateLogger<PostgresWorkerRegistry>());
    }

    public static PostgresSessionCoordinator CreateCoordinator(IWorkerRegistry workers, TimeProvider? timeProvider = null)
    {
        return new PostgresSessionCoordinator(
            workers,
            CreateScopeFactory(),
            LoggerFactory.Create(_ => { }).CreateLogger<PostgresSessionCoordinator>(),
            timeProvider);
    }
}
