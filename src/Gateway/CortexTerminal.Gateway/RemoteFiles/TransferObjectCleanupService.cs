using CortexTerminal.Gateway.Storage;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CortexTerminal.Gateway.RemoteFiles;

/// <summary>
/// Periodic reaper for remote-file leftovers: flips timed-out pending registry entries to
/// failed so phone polls terminate, removes aged terminal entries, and deletes unconsumed
/// "transfers/" S3 objects. Objects a phone downloaded are normally deleted right after
/// mirroring/consumption; this is the janitor for the paths that never got that far.
/// </summary>
public sealed class TransferObjectCleanupService(
    PendingTransferRegistry registry,
    IS3ObjectBroker storage,
    IOptions<RemoteFilesOptions> options,
    ILogger<TransferObjectCleanupService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var interval = options.Value.CleanupInterval;
        using var timer = new PeriodicTimer(interval);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                var swept = registry.SweepExpired(options.Value.PendingTransferTtl);
                var deleted = await DeleteStaleObjectsAsync(stoppingToken);
                if (swept > 0 || deleted > 0)
                {
                    logger.LogInformation("RemoteFiles cleanup: swept {Swept} registry entries, deleted {Deleted} stale transfer objects.", swept, deleted);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "RemoteFiles cleanup cycle failed; retrying next interval.");
            }
        }
    }

    private async Task<int> DeleteStaleObjectsAsync(CancellationToken ct)
    {
        var cutoff = DateTimeOffset.UtcNow - options.Value.ObjectRetention;
        var objects = await storage.ListByPrefixAsync(TransfersPrefix, ct);
        var deleted = 0;
        foreach (var obj in objects.Where(o => o.LastModified < cutoff))
        {
            await storage.DeleteAsync(obj.Key, ct);
            deleted++;
        }
        return deleted;
    }

    private const string TransfersPrefix = "transfers/";
}
