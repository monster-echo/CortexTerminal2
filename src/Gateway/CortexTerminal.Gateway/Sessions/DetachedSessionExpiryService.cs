using Microsoft.Extensions.Hosting;

namespace CortexTerminal.Gateway.Sessions;

public sealed class DetachedSessionExpiryService(
    ISessionCoordinator sessions,
    IReplayCache replayCache,
    TimeProvider timeProvider) : BackgroundService
{
    private static readonly TimeSpan RecoveryTimeout = TimeSpan.FromSeconds(60);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            var now = timeProvider.GetUtcNow();

            foreach (var sessionId in sessions.ExpireDetachedSessions(now))
            {
                replayCache.Clear(sessionId);
            }

            foreach (var sessionId in sessions.ExpireRecoveringSessions(now - RecoveryTimeout))
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
