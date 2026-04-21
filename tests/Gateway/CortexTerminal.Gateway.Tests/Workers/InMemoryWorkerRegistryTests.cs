using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Workers;

public sealed class InMemoryWorkerRegistryTests
{
    [Fact]
    public async Task SetWorkerOwner_DoesNotAllowConcurrentOwnershipStealing()
    {
        var registry = new InMemoryWorkerRegistry();
        registry.Register("worker-1", "connection-1");
        registry.SetWorkerOwner("worker-1", "user-a");

        using var start = new ManualResetEventSlim(false);
        var tasks = Enumerable.Range(0, 8)
            .Select(_ => Task.Run(() =>
            {
                start.Wait();
                for (var attempt = 0; attempt < 100; attempt++)
                {
                    registry.SetWorkerOwner("worker-1", "user-b");
                }
            }))
            .ToArray();

        start.Set();
        await Task.WhenAll(tasks);

        registry.TryGetWorker("worker-1", out var worker).Should().BeTrue();
        worker.OwnerUserId.Should().Be("user-a");
    }
}
