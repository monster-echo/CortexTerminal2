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

        // Tracked load + SaveChanges instead of ExecuteUpdateAsync: ExecuteUpdate is
        // unsupported by the in-memory provider (it takes the whole host down via the
        // background-service failure policy), and it silently dropped deltas for
        // sessions whose row did not exist yet.
        var sessionIds = snapshot.Select(entry => entry.Key).ToArray();
        var sessions = await db.Sessions
            .Where(s => sessionIds.Contains(s.SessionId))
            .ToDictionaryAsync(s => s.SessionId, cancellationToken);

        foreach (var (sessionId, delta) in snapshot)
        {
            if (sessions.TryGetValue(sessionId, out var session))
            {
                session.BytesIngested += delta;
            }
            else
            {
                // Row not written yet — carry the delta to the next flush so ingested
                // bytes are never lost.
                _sessionBytes.AddOrUpdate(sessionId, delta, (_, current) => current + delta);
            }
        }

        await db.SaveChangesAsync(cancellationToken);
    }
}
