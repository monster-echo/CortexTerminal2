using CortexTerminal.Worker.Metrics;
using FluentAssertions;

namespace CortexTerminal.Worker.Tests.Metrics;

public class WindowsSystemMetricsCollectorTests
{
    [Fact]
    public void ComputeCpuPercent_ReturnsBusyFraction()
    {
        // Δtotal = 100, Δidle = 30 → busy 70%
        var cpu = WindowsSystemMetricsCollector.ComputeCpuPercent(prevIdle: 10, prevTotal: 100, curIdle: 40, curTotal: 200);
        cpu.Should().BeApproximately(70.0, 0.001);
    }

    [Fact]
    public void ComputeCpuPercent_IsZero_WhenFullyIdle()
    {
        // Δtotal = 50, Δidle = 50 → busy 0%
        var cpu = WindowsSystemMetricsCollector.ComputeCpuPercent(prevIdle: 0, prevTotal: 100, curIdle: 50, curTotal: 150);
        cpu.Should().Be(0.0);
    }

    [Fact]
    public void ComputeCpuPercent_IsHundred_WhenFullyBusy()
    {
        // Δtotal = 100, Δidle = 0 → busy 100%
        var cpu = WindowsSystemMetricsCollector.ComputeCpuPercent(prevIdle: 50, prevTotal: 100, curIdle: 50, curTotal: 200);
        cpu.Should().BeApproximately(100.0, 0.001);
    }

    [Fact]
    public void ComputeCpuPercent_Throws_WhenDeltaIsZero()
    {
        var act = () => WindowsSystemMetricsCollector.ComputeCpuPercent(prevIdle: 100, prevTotal: 200, curIdle: 100, curTotal: 200);
        act.Should().Throw<InvalidOperationException>();
    }
}
