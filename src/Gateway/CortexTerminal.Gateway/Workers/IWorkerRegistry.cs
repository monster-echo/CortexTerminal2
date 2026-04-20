namespace CortexTerminal.Gateway.Workers;

public interface IWorkerRegistry
{
    void Register(string workerId, string connectionId);
    void Unregister(string workerId);
    bool TryGetLeastBusy(out RegisteredWorker worker);
}

public sealed record RegisteredWorker(string WorkerId, string ConnectionId);
