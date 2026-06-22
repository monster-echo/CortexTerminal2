using System.Collections.Concurrent;
using System.Threading;
using CortexTerminal.Gateway.Data;
using Microsoft.EntityFrameworkCore;

namespace CortexTerminal.Gateway.Stats;

public sealed class SessionStatsService : ISessionStatsService
{
    private readonly ConcurrentDictionary<string, long> _sessionBytes = new();
    private readonly ConcurrentDictionary<string, long> _userBytes = new();
    private readonly IDbContextFactory<AppDbContext> _contextFactory;

    public SessionStatsService(IDbContextFactory<AppDbContext> contextFactory)
    {
        _contextFactory = contextFactory;
    }

    public void RecordBytes(string sessionId, string userId, int byteCount)
    {
        if (byteCount <= 0) return;
        _sessionBytes.AddOrUpdate(sessionId, byteCount, (_, current) => current + byteCount);
        _userBytes.AddOrUpdate(userId, byteCount, (_, current) => current + byteCount);
    }

    public long GetSessionBytes(string sessionId) =>
        _sessionBytes.TryGetValue(sessionId, out var value) ? value : 0;

    public long GetUserBytes(string userId) =>
        _userBytes.TryGetValue(userId, out var value) ? value : 0;

    public IReadOnlyDictionary<string, long> GetAllSessionBytes() => _sessionBytes;

    public IReadOnlyDictionary<string, long> GetAllUserBytes() => _userBytes;

    public async Task FlushAsync(CancellationToken cancellationToken)
    {
        if (_sessionBytes.IsEmpty) return;

        var snapshot = _sessionBytes.ToArray();
        _sessionBytes.Clear();

        await using var db = await _contextFactory.CreateDbContextAsync(cancellationToken);

        foreach (var (sessionId, delta) in snapshot)
        {
            await db.Sessions
                .Where(s => s.SessionId == sessionId)
                .ExecuteUpdateAsync(s => s.SetProperty(e => e.BytesIngested, e => e.BytesIngested + delta), cancellationToken);
        }
    }
}
