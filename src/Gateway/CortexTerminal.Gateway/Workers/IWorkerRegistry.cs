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
    /// <summary>
    /// STRICT in-memory count of online workers owned by <paramref name="userId"/>. Used by the
    /// worker-quota gate. Unlike <see cref="GetOnlineWorkersForUser"/>, this does NOT count
    /// null-owner (legacy open-access) workers — they are never "yours" for quota purposes.
    /// </summary>
    int CountOnlineWorkersForUser(string userId);
    IReadOnlyList<RegisteredWorker> GetAllOnline();
    void UpdateMetrics(string workerId, WorkerMetrics? metrics);
    WorkerMetrics? GetMetrics(string workerId);
    /// <summary>记录 Worker 上报的传输端点（LAN 直连 + 可选公网直连），用于端点协商下发。</summary>
    void UpdateTransferEndpoints(string workerId, IReadOnlyList<string> lanEndpoints, string? publicBaseUrl);
}

public sealed record RegisteredWorker(
    string WorkerId,
    string ConnectionId,
    string? OwnerUserId = null,
    DateTimeOffset? LastSeenAtUtc = null,
    IReadOnlyList<string>? LanEndpoints = null,
    string? PublicTransferBaseUrl = null);

public sealed record WorkerMetadata(
    string? Hostname = null,
    string? OperatingSystem = null,
    string? Architecture = null,
    string? Name = null,
    string? Version = null);

public sealed record WorkerMetrics(
    double? CpuUsagePercent = null,
    double? MemoryUsagePercent = null);
