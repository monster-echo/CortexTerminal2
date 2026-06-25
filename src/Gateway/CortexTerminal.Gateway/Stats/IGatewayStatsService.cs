namespace CortexTerminal.Gateway.Stats;

public interface IGatewayStatsService
{
    void ClientConnected();
    void ClientDisconnected();
    void RecordBytesTransferred(int byteCount);
    void TouchHttpUser(string userId);
    GatewayStatsSnapshot GetSnapshot();
    IReadOnlyList<HourlyStatsPoint> GetHourlyHistory(int hours);
    void CaptureSnapshot();
}

public sealed record GatewayStatsSnapshot(
    int ConnectedClients,
    int OnlineWorkers,
    int ActiveSessions,
    int DetachedSessions,
    long TotalBytesTransferred,
    DateTimeOffset StartedAtUtc,
    long TotalUsers,
    long TotalSessions,
    long AllocatedMemoryBytes,
    int GcGen0Collections,
    int GcGen1Collections,
    int GcGen2Collections,
    int ThreadCount,
    int FailedLoginIpCount,
    int HttpActiveUserCount);

public sealed record HourlyStatsPoint(
    DateTimeOffset Timestamp,
    int ConnectedClients,
    int OnlineWorkers,
    int ActiveSessions,
    long BytesTransferred);