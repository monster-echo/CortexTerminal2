using System.Collections.Concurrent;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Workers;

public sealed class InMemoryWorkerRegistryTests
{
    [Fact]
    public async Task SetWorkerOwner_DoesNotAllowConcurrentOwnershipStealing()
    {
        for (var attempt = 0; attempt < 250; attempt++)
        {
            var registry = new InMemoryWorkerRegistry();
            registry.Register("worker-1", "connection-1");

            var start = new ManualResetEventSlim(false);
            var finished = new CountdownEvent(8);
            var observedOwners = new ConcurrentQueue<string>();

            var poller = Task.Run(() =>
            {
                string? lastObservedOwner = null;
                while (finished.CurrentCount > 0)
                {
                    if (registry.TryGetWorker("worker-1", out var worker) &&
                        worker.OwnerUserId is { } owner &&
                        owner != lastObservedOwner)
                    {
                        observedOwners.Enqueue(owner);
                        lastObservedOwner = owner;
                    }

                    Thread.SpinWait(100);
                }
            });

            var tasks = new[]
            {
                Task.Run(() => ClaimOwner(start, finished, registry, "user-a")),
                Task.Run(() => ClaimOwner(start, finished, registry, "user-b")),
                Task.Run(() => ClaimOwner(start, finished, registry, "user-a")),
                Task.Run(() => ClaimOwner(start, finished, registry, "user-b")),
                Task.Run(() => ClaimOwner(start, finished, registry, "user-a")),
                Task.Run(() => ClaimOwner(start, finished, registry, "user-b")),
                Task.Run(() => ClaimOwner(start, finished, registry, "user-a")),
                Task.Run(() => ClaimOwner(start, finished, registry, "user-b"))
            };

            start.Set();
            await Task.WhenAll(tasks);
            await poller;

            observedOwners.Should().NotBeEmpty();
            observedOwners.Distinct().Count().Should().BeLessThanOrEqualTo(1);
        }
    }

    private static void ClaimOwner(
        ManualResetEventSlim start,
        CountdownEvent finished,
        InMemoryWorkerRegistry registry,
        string ownerUserId)
    {
        start.Wait();
        registry.SetWorkerOwner("worker-1", ownerUserId);
        Thread.Sleep(1);
        finished.Signal();
    }
}
