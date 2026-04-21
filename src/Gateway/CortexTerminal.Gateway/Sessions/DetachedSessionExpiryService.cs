using Microsoft.Extensions.Hosting;

namespace CortexTerminal.Gateway.Sessions;

public sealed class DetachedSessionExpiryService(
    ISessionCoordinator sessions,
    IReplayCache replayCache,
    TimeProvider timeProvider) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            foreach (var sessionId in sessions.ExpireDetachedSessions(timeProvider.GetUtcNow()))
            {
                replayCache.Clear(sessionId);
            }

            try
            {
                await Task.Delay(TimeSpan.FromSeconds(15), stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
        }
    }
}
