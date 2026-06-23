using CortexTerminal.Gateway.Data;

namespace CortexTerminal.Gateway.Workers;

public interface IWorkerRegistry
{
    void Register(string workerId, string connectionId, string? ownerUserId = null);
    void Unregister(string workerId);
    bool TryGetLeastBusy(out RegisteredWorker worker);
    bool TryGetLeastBusyForUser(string userId, out RegisteredWorker worker);
    bool TryGetWorker(string workerId, out RegisteredWorker worker);
    RegisteredWorker? FindByConnectionId(string connectionId);
    IReadOnlyList<RegisteredWorker> GetWorkersForUser(string userId);
    bool SetWorkerOwner(string workerId, string ownerUserId);
    void PersistMetadata(string workerId, WorkerMetadata? metadata);
    IReadOnlyList<RegisteredWorker> GetOnlineWorkersForUser(string userId);
    Task<IReadOnlyList<WorkerRecord>> GetAllWorkersForUserAsync(string userId);
    int GetOnlineCount();
    IReadOnlyList<RegisteredWorker> GetAllOnline();
    void UpdateMetrics(string workerId, WorkerMetrics? metrics);
    WorkerMetrics? GetMetrics(string workerId);
}

public sealed record RegisteredWorker(
    string WorkerId,
    string ConnectionId,
    string? OwnerUserId = null,
    DateTimeOffset? LastSeenAtUtc = null);

public sealed record WorkerMetadata(
    string? Hostname = null,
    string? OperatingSystem = null,
    string? Architecture = null,
    string? Name = null,
    string? Version = null);

public sealed record WorkerMetrics(
    double? CpuUsagePercent = null,
    double? MemoryUsagePercent = null,
    ulong? MemoryUsedBytes = null,
    ulong? MemoryTotalBytes = null,
    DateTimeOffset? CapturedAtUtc = null);
