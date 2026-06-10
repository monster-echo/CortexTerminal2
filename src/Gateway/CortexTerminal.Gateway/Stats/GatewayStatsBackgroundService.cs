namespace CortexTerminal.Gateway.Stats;

public sealed class GatewayStatsBackgroundService(IGatewayStatsService stats) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromHours(1));

        while (!stoppingToken.IsCancellationRequested)
        {
            await timer.WaitForNextTickAsync(stoppingToken);
            stats.CaptureSnapshot();
        }
    }
}
