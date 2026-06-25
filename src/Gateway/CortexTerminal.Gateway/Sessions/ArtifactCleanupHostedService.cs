using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Gateway.Sessions;

/// <summary>
/// Background sweeper that periodically polls for artifacts whose ExpiresAtUtc has passed
/// and removes them from S3 + DB. Acts as a backstop in case artifact TTLs slip past their
/// deadline without a session-terminate signal firing.
/// </summary>
public sealed class ArtifactCleanupHostedService(
    ArtifactService artifacts,
    TimeProvider timeProvider,
    ILogger<ArtifactCleanupHostedService> logger) : BackgroundService
{
    private static readonly TimeSpan SweepInterval = TimeSpan.FromMinutes(5);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var cleaned = await artifacts.CleanExpiredAsync(stoppingToken);
                if (cleaned > 0)
                {
                    logger.LogInformation("ArtifactCleanup swept {Count} expired artifacts at {Time}.",
                        cleaned, timeProvider.GetUtcNow());
                }
            }
            catch (Exception ex) when (!stoppingToken.IsCancellationRequested)
            {
                logger.LogWarning(ex, "ArtifactCleanup sweep failed; will retry next interval.");
            }

            try
            {
                await Task.Delay(SweepInterval, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
        }
    }
}
