using System.Runtime.InteropServices;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Metrics;

/// <summary>
/// Windows CPU/memory sampler via P/Invoke. CPU uses GetSystemTimes (two
/// samples → idle/total delta, same math as the Linux collector); memory uses
/// GlobalMemoryStatusEx.dwMemoryLoad which is already a usage percentage.
/// </summary>
public sealed class WindowsSystemMetricsCollector : ISystemMetricsCollector
{
    private readonly ILogger<WindowsSystemMetricsCollector> _logger;
    private ulong _prevIdle;
    private ulong _prevTotal;
    private bool _hasPreviousSample;

    public WindowsSystemMetricsCollector(ILogger<WindowsSystemMetricsCollector> logger)
    {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            throw new PlatformNotSupportedException("WindowsSystemMetricsCollector only supports Windows.");
        }
        _logger = logger;
    }

    public Task<WorkerMetricsSnapshot?> SnapshotAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!GetSystemTimes(out var idle, out var kernel, out var user))
        {
            throw new InvalidOperationException($"GetSystemTimes failed (Win32 error {Marshal.GetLastWin32Error()}).");
        }

        var curIdle = idle.Value;
        var curTotal = kernel.Value + user.Value; // kernel already includes idle
        var memory = ReadMemoryUsagePercent();

        if (!_hasPreviousSample)
        {
            _prevIdle = curIdle;
            _prevTotal = curTotal;
            _hasPreviousSample = true;
            return Task.FromResult<WorkerMetricsSnapshot?>(null);
        }

        var cpu = ComputeCpuPercent(_prevIdle, _prevTotal, curIdle, curTotal);
        _prevIdle = curIdle;
        _prevTotal = curTotal;
        return Task.FromResult<WorkerMetricsSnapshot?>(new WorkerMetricsSnapshot(Math.Clamp(cpu, 0, 100), Math.Clamp(memory, 0, 100)));
    }

    private double ReadMemoryUsagePercent()
    {
        var status = new MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf<MEMORYSTATUSEX>() };
        if (!GlobalMemoryStatusEx(ref status))
        {
            throw new InvalidOperationException($"GlobalMemoryStatusEx failed (Win32 error {Marshal.GetLastWin32Error()}).");
        }
        return status.dwMemoryLoad;
    }

    /// <summary>CPU% from two idle/total readings: (Δtotal − Δidle) / Δtotal × 100.</summary>
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

    [StructLayout(LayoutKind.Sequential)]
    private struct FILETIME
    {
        public uint dwLowDateTime;
        public uint dwHighDateTime;
        public readonly ulong Value => ((ulong)dwHighDateTime << 32) | dwLowDateTime;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MEMORYSTATUSEX
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemTimes(out FILETIME idleTime, out FILETIME kernelTime, out FILETIME userTime);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

    public void Dispose() { }
}
