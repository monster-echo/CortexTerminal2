using System.Runtime.InteropServices;
using CortexTerminal.Worker.Metrics;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;

namespace CortexTerminal.Worker.Tests.Metrics;

public class MacSystemMetricsCollectorTests
{
    [Fact]
    public void ComputeCpuPercent_ReturnsBusyFraction()
    {
        var cpu = MacSystemMetricsCollector.ComputeCpuPercent(prevIdle: 10, prevTotal: 100, curIdle: 40, curTotal: 200);
        cpu.Should().BeApproximately(70.0, 0.001);
    }

    [Fact]
    public void ComputeCpuPercent_IsZero_WhenFullyIdle()
    {
        var cpu = MacSystemMetricsCollector.ComputeCpuPercent(prevIdle: 0, prevTotal: 100, curIdle: 50, curTotal: 150);
        cpu.Should().Be(0.0);
    }

    [Fact]
    public void ComputeCpuPercent_Throws_WhenDeltaIsZero()
    {
        var act = () => MacSystemMetricsCollector.ComputeCpuPercent(prevIdle: 100, prevTotal: 200, curIdle: 100, curTotal: 200);
        act.Should().Throw<InvalidOperationException>();
    }

    /// <summary>
    /// Smoke-test that the real mach APIs (host_processor_info + host_statistics64
    /// + sysctl) can be called without crashing and return reasonable values.
    /// Skipped on non-macOS (constructor guards OSX).
    /// </summary>
    [Fact]
    public async Task SnapshotAsync_ReadsRealMetrics_FromMach()
    {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.OSX)) return;

        using var collector = new MacSystemMetricsCollector(NullLogger<MacSystemMetricsCollector>.Instance);
        // first call — priming (no previous sample → null)
        (await collector.SnapshotAsync()).Should().BeNull();

        await Task.Delay(200);
        var snapshot = await collector.SnapshotAsync();
        snapshot.Should().NotBeNull();
        snapshot!.CpuUsagePercent.Should().BeInRange(0, 100);
        snapshot.MemoryUsagePercent.Should().BeGreaterThan(0, "host has RAM in use");
    }
}
