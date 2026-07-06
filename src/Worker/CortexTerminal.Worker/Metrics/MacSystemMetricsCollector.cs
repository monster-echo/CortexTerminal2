using System.Runtime.InteropServices;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Metrics;

/// <summary>
/// macOS CPU/memory sampler via mach kernel APIs — zero subprocess, zero text
/// parsing. CPU: host_processor_info(PROCESSOR_CPU_LOAD_INFO) gives per-core
/// tick counts; two samples → idle/total delta. Memory: host_statistics64
/// (HOST_VM_INFO64) active+wired pages × page size over total physical memory
/// from sysctl hw.memsize. Page size from sysctl hw.pagesize (vm_kernel_page_size
/// is unstable under .NET P/Invoke).
/// </summary>
public sealed class MacSystemMetricsCollector : ISystemMetricsCollector
{
    private readonly ILogger<MacSystemMetricsCollector> _logger;
    private ulong _prevIdle;
    private ulong _prevTotal;
    private bool _hasPreviousSample;

    private const int HOST_VM_INFO64 = 4;
    private const int PROCESSOR_CPU_LOAD_INFO = 2;

    public MacSystemMetricsCollector(ILogger<MacSystemMetricsCollector> logger)
    {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            throw new PlatformNotSupportedException("MacSystemMetricsCollector only supports macOS.");
        }
        _logger = logger;
    }

    public Task<WorkerMetricsSnapshot?> SnapshotAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var (idle, total) = ReadCpuTicks();
        var memory = ReadMemoryUsagePercent();

        if (!_hasPreviousSample)
        {
            _prevIdle = idle;
            _prevTotal = total;
            _hasPreviousSample = true;
            return Task.FromResult<WorkerMetricsSnapshot?>(null);
        }

        var cpu = ComputeCpuPercent(_prevIdle, _prevTotal, idle, total);
        _prevIdle = idle;
        _prevTotal = total;
        return Task.FromResult<WorkerMetricsSnapshot?>(new WorkerMetricsSnapshot(Math.Clamp(cpu, 0, 100), Math.Clamp(memory, 0, 100)));
    }

    private static (ulong Idle, ulong Total) ReadCpuTicks()
    {
        var host = mach_host_self();
        if (host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, out var processorCount, out var cpuInfo, out var cpuInfoCount) != 0)
        {
            throw new InvalidOperationException("host_processor_info failed.");
        }
        try
        {
            ulong user = 0, system = 0, idle = 0, nice = 0;
            for (uint i = 0; i < processorCount; i++)
            {
                var offset = (int)(i * 4) * sizeof(int);
                user += (ulong)Marshal.ReadInt32(cpuInfo, offset + 0 * sizeof(int));
                system += (ulong)Marshal.ReadInt32(cpuInfo, offset + 1 * sizeof(int));
                idle += (ulong)Marshal.ReadInt32(cpuInfo, offset + 2 * sizeof(int));
                nice += (ulong)Marshal.ReadInt32(cpuInfo, offset + 3 * sizeof(int));
            }
            return (idle, user + system + idle + nice);
        }
        finally
        {
            vm_deallocate(mach_task_self(), cpuInfo, cpuInfoCount * (uint)sizeof(int));
        }
    }

    private static double ReadMemoryUsagePercent()
    {
        var host = mach_host_self();
        IntPtr buffer = Marshal.AllocHGlobal(4096);
        try
        {
            uint count = 4096 / (uint)sizeof(int);
            if (host_statistics64(host, HOST_VM_INFO64, buffer, ref count) != 0)
            {
                throw new InvalidOperationException("host_statistics64(HOST_VM_INFO64) failed.");
            }
            // vm_statistics64: free, active, inactive, wire, ...
            long active = Marshal.ReadInt32(buffer, 1 * sizeof(int));
            long wire = Marshal.ReadInt32(buffer, 3 * sizeof(int));

            if (!SysctlUInt64("hw.memsize", out var rawTotal) || rawTotal <= 0) return 0;
            if (!SysctlUInt64("hw.pagesize", out var rawPage) || rawPage <= 0) return 0;
            long totalBytes = (long)rawTotal;
            long pageBytes = (long)rawPage;

            var usedBytes = (active + wire) * pageBytes;
            return usedBytes * 100.0 / totalBytes;
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private static bool SysctlUInt64(string name, out ulong value)
    {
        value = 0;
        nuint size = (nuint)sizeof(ulong);
        return sysctlbyname(name, out value, ref size, IntPtr.Zero, 0) == 0;
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
        return (totalDelta - idleDelta) * 100.0 / totalDelta;
    }

    [DllImport("libSystem.dylib")]
    private static extern uint mach_host_self();

    [DllImport("libSystem.dylib")]
    private static extern uint host_statistics64(uint host, int flavor, IntPtr hostInfo, ref uint hostInfoCount);

    [DllImport("libSystem.dylib")]
    private static extern uint host_processor_info(uint host, int flavor, out uint processorCount, out IntPtr cpuInfo, out uint cpuInfoCount);

    [DllImport("libSystem.dylib")]
    private static extern uint mach_task_self();

    [DllImport("libSystem.dylib")]
    private static extern uint vm_deallocate(uint task, IntPtr address, uint size);

    [DllImport("libSystem.dylib")]
    private static extern uint sysctlbyname(string name, out ulong oldValue, ref nuint oldSize, IntPtr newp, nuint newLen);

    public void Dispose() { }
}
