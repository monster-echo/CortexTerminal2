using System.Threading;
using System.Threading.Tasks;

namespace CortexTerminal.Worker.Metrics;

/// <summary>
/// Platform-agnostic sampler for worker CPU/memory usage. Implementations read
/// the host OS's native counters (Linux /proc, macOS top, Windows P/Invoke).
/// </summary>
/// <remarks>
/// <b>Semantics</b>: return null when a sample is momentarily unavailable
/// (e.g. first call before two readings exist); throw when sampling genuinely
/// fails. The metrics loop treats exceptions as transient (LogWarning + continue).
/// </remarks>
public interface ISystemMetricsCollector : IDisposable
{
    Task<WorkerMetricsSnapshot?> SnapshotAsync(CancellationToken cancellationToken = default);
}
