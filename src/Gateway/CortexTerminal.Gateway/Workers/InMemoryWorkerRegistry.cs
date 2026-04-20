using System.Collections.Concurrent;

namespace CortexTerminal.Gateway.Workers;

public sealed class InMemoryWorkerRegistry : IWorkerRegistry
{
    private readonly ConcurrentDictionary<string, RegisteredWorker> _workers = new();

    public void Register(string workerId, string connectionId)
        => _workers[workerId] = new RegisteredWorker(workerId, connectionId);

    public void Unregister(string workerId)
        => _workers.TryRemove(workerId, out _);

    public bool TryGetLeastBusy(out RegisteredWorker worker)
    {
        // Phase 1: single-session, just pick any available worker
        foreach (var kvp in _workers)
        {
            worker = kvp.Value;
            return true;
        }
        worker = default!;
        return false;
    }
}
