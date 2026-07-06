using System.Globalization;
using System.Runtime.InteropServices;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Metrics;

public sealed class LinuxSystemMetricsCollector : ISystemMetricsCollector
{
    private readonly ILogger<LinuxSystemMetricsCollector> _logger;
    private readonly TimeSpan _sampleInterval;
    private readonly Func<string, string?> _readProcFile;
    private ulong _prevIdle;
    private ulong _prevTotal;
    private bool _hasPreviousSample;

    public LinuxSystemMetricsCollector(ILogger<LinuxSystemMetricsCollector> logger, TimeSpan? sampleInterval = null)
    {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
        {
            throw new PlatformNotSupportedException("LinuxSystemMetricsCollector only supports Linux.");
        }
        _logger = logger;
        _sampleInterval = sampleInterval ?? TimeSpan.FromSeconds(1);
        _readProcFile = ReadProcFileDefault;
    }

    internal LinuxSystemMetricsCollector(ILogger<LinuxSystemMetricsCollector> logger, Func<string, string?> readProcFile, TimeSpan? sampleInterval = null)
        : this(logger, sampleInterval)
    {
        _readProcFile = readProcFile;
    }

    public async Task<WorkerMetricsSnapshot?> SnapshotAsync(CancellationToken cancellationToken = default)
    {
        var firstSample = ReadCpuSample();
        if (!_hasPreviousSample)
        {
            _prevIdle = firstSample.Idle;
            _prevTotal = firstSample.Total;
            _hasPreviousSample = true;
            await Task.Delay(_sampleInterval, cancellationToken);
            var secondSample = ReadCpuSample();
            var (cpu, _, _) = AdvanceAndGetCpu(secondSample);
            return new WorkerMetricsSnapshot(
                Math.Clamp(cpu, 0, 100),
                ReadMemoryUsagePercent());
        }

        var current = ReadCpuSample();
        var (cpuPercent, _, _) = AdvanceAndGetCpu(current);
        return new WorkerMetricsSnapshot(
            Math.Clamp(cpuPercent, 0, 100),
            ReadMemoryUsagePercent());
    }

    private (double CpuPercent, ulong CurIdle, ulong CurTotal) AdvanceAndGetCpu((ulong Idle, ulong Total) current)
    {
        var cpuPercent = ComputeCpuPercent(_prevIdle, _prevTotal, current.Idle, current.Total);
        _prevIdle = current.Idle;
        _prevTotal = current.Total;
        return (cpuPercent, current.Idle, current.Total);
    }

    private (ulong Idle, ulong Total) ReadCpuSample()
    {
        var statLine = _readProcFile("/proc/stat");
        if (string.IsNullOrEmpty(statLine))
        {
            throw new InvalidOperationException("/proc/stat returned empty content.");
        }
        return ParseProcStat(statLine);
    }

    private double ReadMemoryUsagePercent()
    {
        var meminfo = _readProcFile("/proc/meminfo");
        if (string.IsNullOrEmpty(meminfo))
        {
            throw new InvalidOperationException("/proc/meminfo returned empty content.");
        }
        return ParseProcMeminfoUsagePercent(meminfo);
    }

    internal static (ulong Idle, ulong Total) ParseProcStat(string statLine)
    {
        var firstLine = statLine.AsSpan().TrimStart();
        var newlineIndex = firstLine.IndexOf('\n');
        if (newlineIndex >= 0)
        {
            firstLine = firstLine.Slice(0, newlineIndex);
        }

        if (!firstLine.StartsWith("cpu", StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"/proc/stat first line is not a cpu aggregate: {firstLine.ToString()}");
        }

        var labelEnd = firstLine.IndexOf(' ');
        if (labelEnd < 0)
        {
            throw new InvalidOperationException($"/proc/stat first line missing values: {firstLine.ToString()}");
        }

        var valuesSpan = firstLine.Slice(labelEnd + 1).Trim();
        var parts = new List<ulong>(8);
        while (!valuesSpan.IsEmpty)
        {
            var space = valuesSpan.IndexOf(' ');
            ReadOnlySpan<char> token;
            if (space < 0)
            {
                token = valuesSpan;
                valuesSpan = ReadOnlySpan<char>.Empty;
            }
            else
            {
                token = valuesSpan.Slice(0, space);
                valuesSpan = valuesSpan.Slice(space + 1).TrimStart();
            }

            if (token.IsEmpty) continue;
            if (!ulong.TryParse(token, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value))
            {
                throw new InvalidOperationException($"/proc/stat value is not numeric: {token.ToString()}");
            }
            parts.Add(value);
        }

        if (parts.Count < 4)
        {
            throw new InvalidOperationException($"/proc/stat expected at least 4 cpu counters, got {parts.Count}.");
        }

        var idle = parts[3];
        if (parts.Count > 4) idle += parts[4];

        var total = 0UL;
        foreach (var value in parts)
        {
            total += value;
        }

        return (idle, total);
    }

    internal static double ComputeCpuPercent(ulong prevIdle, ulong prevTotal, ulong curIdle, ulong curTotal)
    {
        var totalDelta = curTotal - prevTotal;
        if (totalDelta == 0)
        {
            throw new InvalidOperationException("cpu sample delta is zero.");
        }
        var idleDelta = curIdle - prevIdle;
        var used = totalDelta - idleDelta;
        return used * 100.0 / totalDelta;
    }

    private static double ParseProcMeminfoUsagePercent(string meminfo)
    {
        ulong? total = null;
        ulong? available = null;

        foreach (var rawLine in meminfo.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (rawLine.StartsWith("MemTotal:", StringComparison.OrdinalIgnoreCase))
            {
                total = ReadKbValue(rawLine);
            }
            else if (rawLine.StartsWith("MemAvailable:", StringComparison.OrdinalIgnoreCase))
            {
                available = ReadKbValue(rawLine);
            }
            if (total.HasValue && available.HasValue) break;
        }

        if (!total.HasValue)
        {
            throw new InvalidOperationException("MemTotal missing from /proc/meminfo.");
        }
        if (!available.HasValue)
        {
            throw new InvalidOperationException("MemAvailable missing from /proc/meminfo.");
        }

        if (total.Value == 0) return 0;
        var usedKb = total.Value > available.Value ? total.Value - available.Value : 0UL;
        return usedKb * 100.0 / total.Value;
    }

    private static ulong ReadKbValue(string line)
    {
        var colon = line.IndexOf(':');
        if (colon < 0)
        {
            throw new InvalidOperationException($"/proc/meminfo line missing colon: {line}");
        }
        var rest = line.AsSpan().Slice(colon + 1).Trim();
        var space = rest.IndexOf(' ');
        var numberSpan = space < 0 ? rest : rest.Slice(0, space);
        if (!ulong.TryParse(numberSpan, NumberStyles.Integer, CultureInfo.InvariantCulture, out var kb))
        {
            throw new InvalidOperationException($"/proc/meminfo value not numeric: {line}");
        }
        return kb;
    }

    private static string? ReadProcFileDefault(string path)
    {
        if (!File.Exists(path)) return null;
        return File.ReadAllText(path);
    }

    public void Dispose()
    {
    }
}
