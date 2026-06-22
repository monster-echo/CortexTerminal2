using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Gateway.Sessions;

public sealed class DetachedSessionExpiryService(
    ISessionCoordinator sessions,
    ReplayCoordinator replayCoordinator,
    TimeProvider timeProvider,
    ILogger<DetachedSessionExpiryService> logger) : BackgroundService
{
    private static readonly TimeSpan RecoveryTimeout = TimeSpan.FromSeconds(60);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            foreach (var sessionId in await sessions.ExpireRecoveringSessions(timeProvider.GetUtcNow() - RecoveryTimeout))
            {
                logger.LogInformation("session.expired {SessionId} reason=recovery-timeout", sessionId);
                replayCoordinator.AbortReplay(sessionId);
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
