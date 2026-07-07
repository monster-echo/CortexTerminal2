using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Agent;

/// <summary>
/// Background service that keeps the local Corterm agent skill in sync with the remote source.
/// Fetches once on startup (covers the no-cache first install), then every 6 hours. When the
/// fetched content's sha256 differs from the cache, it persists and reinstalls — so pushing a
/// skill edit to the repo's <c>skills/corterm-artifacts/</c> propagates to every running worker
/// without a redeploy. Transient failures are logged and the cache is left untouched; the next
/// tick retries.
/// </summary>
internal sealed class AgentSkillSyncService : BackgroundService
{
    private static readonly TimeSpan RefreshInterval = TimeSpan.FromHours(6);

    private readonly AgentSkillSource _source;
    private readonly AgentSkillInstaller _installer;
    private readonly HttpClient _http;
    private readonly ILogger<AgentSkillSyncService> _logger;

    public AgentSkillSyncService(
        AgentSkillSource source,
        AgentSkillInstaller installer,
        HttpClient http,
        ILogger<AgentSkillSyncService> logger)
    {
        _source = source;
        _installer = installer;
        _http = http;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await RefreshOnceAsync("startup", stoppingToken).ConfigureAwait(false);

        using var timer = new PeriodicTimer(RefreshInterval);
        try
        {
            while (await timer.WaitForNextTickAsync(stoppingToken).ConfigureAwait(false))
            {
                await RefreshOnceAsync("scheduled", stoppingToken).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
    }

    /// <summary>
    /// Fetch the latest skill content; on change, persist + reinstall. Swallows transient
    /// network failures (logged as warnings) so a flaky connection never crashes the worker or
    /// wipes the cache. Propagates only true service-stopping cancellation.
    /// </summary>
    internal async Task RefreshOnceAsync(string reason, CancellationToken cancellationToken)
    {
        try
        {
            var (skillMd, codexMd) = await _source.FetchAsync(_http, cancellationToken).ConfigureAwait(false);
            var newSha = AgentSkillInstaller.ComputeContentSha(skillMd, codexMd);
            var cachedSha = await _installer.GetCachedShaAsync(cancellationToken).ConfigureAwait(false);

            if (string.Equals(newSha, cachedSha, StringComparison.OrdinalIgnoreCase))
            {
                return; // unchanged — no reinstall needed
            }

            await _installer.SaveCacheAndInstallAsync(skillMd, codexMd, cancellationToken).ConfigureAwait(false);
            _logger.LogInformation("Corterm agent skill updated ({Reason}, sha {Sha}).", reason, newSha[..8]);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw; // service is stopping — let it propagate
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to refresh Corterm agent skill ({Reason}); keeping existing cache.", reason);
        }
    }
}
