namespace CortexTerminal.Worker.Metrics;

/// <summary>
/// One CPU/memory reading. Both values are clamped to [0, 100] percent.
/// </summary>
public sealed record WorkerMetricsSnapshot(
    double CpuUsagePercent,
    double MemoryUsagePercent);
