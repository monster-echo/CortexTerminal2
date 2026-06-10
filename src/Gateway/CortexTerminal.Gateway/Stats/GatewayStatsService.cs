using System.Diagnostics;
using System.Threading;
using CortexTerminal.Gateway.Auth;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using Microsoft.Extensions.DependencyInjection;

namespace CortexTerminal.Gateway.Stats;

public sealed class GatewayStatsService : IGatewayStatsService
{
    private int _connectedClients;
    private long _totalBytesTransferred;
    private readonly DateTimeOffset _startedAtUtc = DateTimeOffset.UtcNow;

    private readonly IWorkerRegistry _workers;
    private readonly ISessionCoordinator _sessions;
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly FailedAttemptTracker _failedAttempts;

    private readonly HourlyStatsPoint[] _hourlyHistory = new HourlyStatsPoint[24];
    private int _hourlyIndex = -1;
    private readonly object _hourlyLock = new();

    public GatewayStatsService(
        IWorkerRegistry workers,
        ISessionCoordinator sessions,
        IServiceScopeFactory scopeFactory,
        FailedAttemptTracker failedAttempts)
    {
        _workers = workers;
        _sessions = sessions;
        _scopeFactory = scopeFactory;
        _failedAttempts = failedAttempts;
    }

    public void ClientConnected() => Interlocked.Increment(ref _connectedClients);
    public void ClientDisconnected() => Interlocked.Decrement(ref _connectedClients);
    public void RecordBytesTransferred(int byteCount) => Interlocked.Add(ref _totalBytesTransferred, byteCount);

    public GatewayStatsSnapshot GetSnapshot()
    {
        var (active, detached) = _sessions.GetAllSessionCounts();
        var onlineWorkers = _workers.GetOnlineCount();
        var connectedClients = Interlocked.CompareExchange(ref _connectedClients, 0, 0);
        var totalBytes = Interlocked.Read(ref _totalBytesTransferred);

        var process = Process.GetCurrentProcess();
        process.Refresh();

        long totalUsers = 0;
        long totalSessions = 0;
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<Data.AppDbContext>();
            totalUsers = db.Users.LongCount();
            totalSessions = db.Sessions.LongCount();
        }
        catch
        {
            // DB unavailable in some configurations
        }

        return new GatewayStatsSnapshot(
            ConnectedClients: connectedClients,
            OnlineWorkers: onlineWorkers,
            ActiveSessions: active,
            DetachedSessions: detached,
            TotalBytesTransferred: totalBytes,
            StartedAtUtc: _startedAtUtc,
            TotalUsers: totalUsers,
            TotalSessions: totalSessions,
            AllocatedMemoryBytes: process.WorkingSet64,
            GcGen0Collections: GC.CollectionCount(0),
            GcGen1Collections: GC.CollectionCount(1),
            GcGen2Collections: GC.CollectionCount(2),
            ThreadCount: process.Threads.Count,
            FailedLoginIpCount: _failedAttempts.GetTrackedIpCount());
    }

    public IReadOnlyList<HourlyStatsPoint> GetHourlyHistory(int hours)
    {
        lock (_hourlyLock)
        {
            if (_hourlyIndex < 0) return [];

            var result = new List<HourlyStatsPoint>();
            var count = Math.Min(hours, _hourlyIndex + 1);

            for (var i = 0; i < count; i++)
            {
                var idx = _hourlyIndex - i;
                if (idx < 0) idx += 24;
                if (_hourlyHistory[idx] is not null)
                    result.Insert(0, _hourlyHistory[idx]!);
            }

            return result;
        }
    }

    public void CaptureSnapshot()
    {
        var clients = Interlocked.CompareExchange(ref _connectedClients, 0, 0);
        var bytes = Interlocked.Read(ref _totalBytesTransferred);
        var onlineWorkers = _workers.GetOnlineCount();
        var (active, _) = _sessions.GetAllSessionCounts();

        var point = new HourlyStatsPoint(
            Timestamp: DateTimeOffset.UtcNow,
            ConnectedClients: clients,
            OnlineWorkers: onlineWorkers,
            ActiveSessions: active,
            BytesTransferred: bytes);

        lock (_hourlyLock)
        {
            _hourlyIndex = (_hourlyIndex + 1) % 24;
            _hourlyHistory[_hourlyIndex] = point;
        }
    }
}
