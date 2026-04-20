using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Hubs;

public sealed class TerminalHubTests
{
    [Fact]
    public void WorkerRegistry_RegisterAndRetrieve_Works()
    {
        var registry = new InMemoryWorkerRegistry();
        registry.Register("w-1", "conn-abc");

        registry.TryGetLeastBusy(out var worker).Should().BeTrue();
        worker.WorkerId.Should().Be("w-1");
        worker.ConnectionId.Should().Be("conn-abc");
    }

    [Fact]
    public void WorkerRegistry_Empty_ReturnsFalse()
    {
        var registry = new InMemoryWorkerRegistry();
        registry.TryGetLeastBusy(out _).Should().BeFalse();
    }

    [Fact]
    public void WorkerRegistry_Unregister_RemovesWorker()
    {
        var registry = new InMemoryWorkerRegistry();
        registry.Register("w-1", "conn-abc");
        registry.Unregister("w-1");

        registry.TryGetLeastBusy(out _).Should().BeFalse();
    }
}
