using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Gateway.Stats;

public sealed class SessionStatsFlusher : BackgroundService
{
    private readonly ISessionStatsService _stats;
    private readonly ILogger<SessionStatsFlusher> _logger;
    private static readonly TimeSpan FlushInterval = TimeSpan.FromSeconds(10);

    public SessionStatsFlusher(ISessionStatsService stats, ILogger<SessionStatsFlusher> logger)
    {
        _stats = stats;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(FlushInterval);
        try
        {
            while (await timer.WaitForNextTickAsync(stoppingToken))
            {
                await _stats.FlushAsync(stoppingToken);
            }
        }
        catch (OperationCanceledException)
        {
            // graceful shutdown
        }
    }
}
