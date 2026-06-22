using System.Collections.Concurrent;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Workers;
using Microsoft.EntityFrameworkCore;

namespace CortexTerminal.Gateway.Sessions;

public sealed class PostgresSessionCoordinator : ISessionCoordinator
{
    private readonly IWorkerRegistry _workers;
    private readonly ConcurrentDictionary<string, SessionRecord> _sessions = new();
    private readonly ConcurrentDictionary<string, DateTimeOffset> _lastTouchBySession = new();
    private readonly object _sync = new();
    private readonly TimeProvider _timeProvider;
    private readonly IDbContextFactory<AppDbContext> _contextFactory;

    private readonly ILogger<PostgresSessionCoordinator> _logger;

    public PostgresSessionCoordinator(
        IWorkerRegistry workers,
        IDbContextFactory<AppDbContext> contextFactory,
        ILogger<PostgresSessionCoordinator> logger,
        TimeProvider? timeProvider = null)
    {
        _workers = workers;
        _contextFactory = contextFactory;
        _logger = logger;
        _timeProvider = timeProvider ?? TimeProvider.System;
    }

    public async Task RecoverActiveSessionsAsync()
    {
        var recoverableStates = new[] { "Attached", "DetachedGracePeriod", "Recovering" };

        List<SessionRecordEntity> entities;
        await using (var db = await _contextFactory.CreateDbContextAsync())
        {
            entities = await db.Sessions
                .Where(e => recoverableStates.Contains(e.AttachmentState))
                .ToListAsync();
        }

        if (entities.Count == 0) return;

        var now = _timeProvider.GetUtcNow();
        var toPersist = new List<SessionRecordEntity>(entities.Count);

        lock (_sync)
        {
            foreach (var entity in entities)
            {
                var wasRecovering = entity.AttachmentState == "Recovering";
                var record = new SessionRecord(
                    entity.SessionId,
                    entity.UserId,
                    entity.WorkerId,
                    WorkerConnectionId: entity.WorkerConnectionId ?? "",
                    entity.Columns,
                    entity.Rows,
                    entity.CreatedAtUtc,
                    LastActivityAtUtc: wasRecovering ? entity.LastActivityAtUtc : now,
                    AttachmentState: SessionAttachmentState.Recovering,
                    AttachedClientConnectionId: null,
                    LeaseExpiresAtUtc: null,
                    Name: entity.Name);

                _sessions[entity.SessionId] = record;
                _logger.LogInformation("session.recovering {SessionId} worker={WorkerId} user={UserId}", entity.SessionId, entity.WorkerId, entity.UserId);

                if (!wasRecovering)
                {
                    entity.AttachmentState = "Recovering";
                    entity.AttachedClientConnectionId = null;
                    toPersist.Add(entity);
                }
            }
        }

        if (toPersist.Count > 0)
        {
            await using var persistDb = await _contextFactory.CreateDbContextAsync();
            foreach (var entity in toPersist)
            {
                var tracked = await persistDb.Sessions.FindAsync(entity.SessionId);
                if (tracked is null) continue;
                tracked.AttachmentState = "Recovering";
                tracked.AttachedClientConnectionId = null;
            }
            await persistDb.SaveChangesAsync();
        }

        _logger.LogInformation("Recovered {Count} active sessions from database", entities.Count);
    }

    public async Task<CreateSessionResult> CreateSessionAsync(string userId, CreateSessionRequest request, string? clientConnectionId, CancellationToken cancellationToken)
    {
        RegisteredWorker worker;

        if (!string.IsNullOrEmpty(request.WorkerId))
        {
            if (!_workers.TryGetWorker(request.WorkerId, out var requested) ||
                (requested.OwnerUserId is not null && requested.OwnerUserId != userId))
            {
                return CreateSessionResult.Failure("worker-not-found");
            }
            worker = requested;
        }
        else
        {
            if (!_workers.TryGetLeastBusyForUser(userId, out var leastBusy))
            {
                return CreateSessionResult.Failure("no-worker-available");
            }
            worker = leastBusy;
        }

        if (!_workers.SetWorkerOwner(worker.WorkerId, userId))
        {
            return CreateSessionResult.Failure("no-worker-available");
        }

        var now = _timeProvider.GetUtcNow();
        var sessionId = $"sess_{Guid.NewGuid():N}";
        var record = new SessionRecord(
            sessionId,
            userId,
            worker.WorkerId,
            worker.ConnectionId,
            request.Columns,
            request.Rows,
            now,
            now,
            AttachedClientConnectionId: clientConnectionId);

        await using (var db = await _contextFactory.CreateDbContextAsync(cancellationToken))
        {
            db.Sessions.Add(new SessionRecordEntity
            {
                SessionId = sessionId,
                UserId = userId,
                WorkerId = worker.WorkerId,
                WorkerConnectionId = worker.ConnectionId,
                Columns = request.Columns,
                Rows = request.Rows,
                CreatedAtUtc = now,
                LastActivityAtUtc = now,
                AttachmentState = "Attached",
                AttachedClientConnectionId = clientConnectionId
            });
            await db.SaveChangesAsync(cancellationToken);
        }

        lock (_sync)
        {
            _sessions[sessionId] = record;
        }

        _logger.LogInformation("session.created {SessionId} worker={WorkerId} user={UserId}", sessionId, worker.WorkerId, userId);

        return CreateSessionResult.Success(new CreateSessionResponse(sessionId, worker.WorkerId));
    }

    public async Task DetachSessionAsync(string userId, string sessionId, DateTimeOffset detachedAtUtc, CancellationToken cancellationToken)
    {
        SessionRecord? staged = null;

        lock (_sync)
        {
            if (!_sessions.TryGetValue(sessionId, out var session) || session.UserId != userId)
            {
                return;
            }

            staged = session with
            {
                AttachedClientConnectionId = null,
                ReplayPending = false,
                LastActivityAtUtc = detachedAtUtc
            };
        }

        await PersistSessionStateAsync(sessionId, "Attached",
            attachedClientConnectionId: null,
            lastActivityAtUtc: detachedAtUtc,
            cancellationToken: cancellationToken);

        lock (_sync)
        {
            if (staged is not null) _sessions[sessionId] = staged;
        }

        _logger.LogInformation("session.client-detached {SessionId} user={UserId}", sessionId, userId);
    }

    public async Task<DeleteSessionResult> DeleteSessionAsync(string userId, string sessionId, CancellationToken cancellationToken)
    {
        bool owned;
        lock (_sync)
        {
            owned = _sessions.TryGetValue(sessionId, out var session) && session.UserId == userId;
        }

        if (!owned)
        {
            return DeleteSessionResult.Failure("session-not-found");
        }

        await using var db = await _contextFactory.CreateDbContextAsync(cancellationToken);
        var entity = await db.Sessions.FindAsync(sessionId, cancellationToken);
        if (entity is not null && string.Equals(entity.UserId, userId, StringComparison.Ordinal))
        {
            db.Sessions.Remove(entity);
            await db.SaveChangesAsync(cancellationToken);
        }

        lock (_sync)
        {
            _sessions.TryRemove(sessionId, out _);
        }

        _logger.LogInformation("session.deleted {SessionId} user={UserId}", sessionId, userId);

        return DeleteSessionResult.Success();
    }

    public async Task<ReattachSessionResult> ReattachSessionAsync(
        string userId,
        ReattachSessionRequest request,
        string clientConnectionId,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        SessionRecord? staged = null;
        string? dbState = null;
        string? dbClient = null;
        bool? dbReplay = null;
        string logMessage = "";
        ReattachSessionResult result;

        lock (_sync)
        {
            if (!_sessions.TryGetValue(request.SessionId, out var session) || session.UserId != userId)
            {
                return ReattachSessionResult.Failure("session-not-found");
            }

            if (session.AttachmentState == SessionAttachmentState.Attached)
            {
                staged = session with
                {
                    AttachedClientConnectionId = clientConnectionId,
                    LeaseExpiresAtUtc = null,
                    ReplayPending = true,
                    LastActivityAtUtc = nowUtc
                };
                dbState = "Attached";
                dbClient = clientConnectionId;
                dbReplay = true;
                logMessage = $"session.reattached {request.SessionId} client={clientConnectionId} (displaced existing)";
                result = ReattachSessionResult.Success();
            }
            else if (session.AttachmentState == SessionAttachmentState.Recovering)
            {
                staged = session with
                {
                    AttachmentState = SessionAttachmentState.Attached,
                    AttachedClientConnectionId = clientConnectionId,
                    LeaseExpiresAtUtc = null,
                    ReplayPending = false,
                    LastActivityAtUtc = nowUtc
                };
                dbState = "Attached";
                dbClient = clientConnectionId;
                logMessage = $"Reattach: {request.SessionId} Recovering → Attached (client={clientConnectionId})";
                result = ReattachSessionResult.Success();
            }
            else if (session.AttachmentState != SessionAttachmentState.DetachedGracePeriod)
            {
                return ReattachSessionResult.Failure("session-expired");
            }
            else if (!session.LeaseExpiresAtUtc.HasValue)
            {
                staged = session with
                {
                    AttachmentState = SessionAttachmentState.Expired,
                    AttachedClientConnectionId = null,
                    LeaseExpiresAtUtc = null,
                    ReplayPending = false,
                    LastActivityAtUtc = nowUtc
                };
                dbState = "Expired";
                result = ReattachSessionResult.Failure("session-detached-without-lease");
            }
            else if (session.LeaseExpiresAtUtc.Value <= nowUtc)
            {
                staged = session with
                {
                    AttachmentState = SessionAttachmentState.Expired,
                    AttachedClientConnectionId = null,
                    LeaseExpiresAtUtc = null,
                    ReplayPending = false,
                    LastActivityAtUtc = nowUtc
                };
                dbState = "Expired";
                result = ReattachSessionResult.Failure("session-expired");
            }
            else
            {
                staged = session with
                {
                    AttachmentState = SessionAttachmentState.Attached,
                    AttachedClientConnectionId = clientConnectionId,
                    LeaseExpiresAtUtc = null,
                    ReplayPending = true,
                    LastActivityAtUtc = nowUtc
                };
                dbState = "Attached";
                dbClient = clientConnectionId;
                dbReplay = true;
                logMessage = $"session.reattached {request.SessionId} client={clientConnectionId} (from DetachedGracePeriod)";
                result = ReattachSessionResult.Success();
            }
        }

        if (dbState is not null)
        {
            await PersistSessionStateAsync(request.SessionId, dbState,
                attachedClientConnectionId: dbClient,
                leaseExpiresAtUtc: null,
                replayPending: dbReplay,
                lastActivityAtUtc: nowUtc,
                cancellationToken: cancellationToken);
        }

        lock (_sync)
        {
            if (staged is not null) _sessions[request.SessionId] = staged;
        }

        if (logMessage.Length > 0)
        {
            _logger.LogInformation("{Message}", logMessage);
        }

        return result;
    }

    public async Task MarkSessionStartFailed(string sessionId, string reason)
    {
        SessionRecord? staged = null;
        DateTimeOffset nowUtc;

        lock (_sync)
        {
            if (!_sessions.TryGetValue(sessionId, out var session)) return;
            nowUtc = _timeProvider.GetUtcNow();
            staged = session with
            {
                AttachmentState = SessionAttachmentState.Exited,
                AttachedClientConnectionId = null,
                ExitCode = null,
                ExitReason = reason,
                ReplayPending = false,
                LeaseExpiresAtUtc = null,
                LastActivityAtUtc = nowUtc
            };
        }

        await PersistSessionStateAsync(sessionId, "Exited",
            attachedClientConnectionId: null,
            exitCode: null,
            exitReason: reason,
            leaseExpiresAtUtc: null,
            replayPending: false,
            lastActivityAtUtc: nowUtc);

        lock (_sync)
        {
            if (staged is not null) _sessions[sessionId] = staged;
        }

        _logger.LogInformation("session.start-failed {SessionId} reason={Reason}", sessionId, reason);
    }

    public async Task RemoveSession(string sessionId)
    {
        _logger.LogInformation("session.removed {SessionId}", sessionId);

        lock (_sync)
        {
            _sessions.TryRemove(sessionId, out _);
        }

        _lastTouchBySession.TryRemove(sessionId, out _);

        await using var db = await _contextFactory.CreateDbContextAsync();
        var entity = await db.Sessions.FindAsync(sessionId);
        if (entity is not null)
        {
            db.Sessions.Remove(entity);
            await db.SaveChangesAsync();
        }
    }

    public async Task MarkSessionExited(string sessionId, int exitCode, string reason)
    {
        SessionRecord? staged = null;
        DateTimeOffset nowUtc;

        lock (_sync)
        {
            if (!_sessions.TryGetValue(sessionId, out var session)) return;
            nowUtc = _timeProvider.GetUtcNow();
            staged = session with
            {
                AttachmentState = SessionAttachmentState.Exited,
                AttachedClientConnectionId = null,
                ExitCode = exitCode,
                ExitReason = reason,
                ReplayPending = false,
                LeaseExpiresAtUtc = null,
                LastActivityAtUtc = nowUtc
            };
        }

        await PersistSessionStateAsync(sessionId, "Exited",
            attachedClientConnectionId: null,
            exitCode: exitCode,
            exitReason: reason,
            leaseExpiresAtUtc: null,
            replayPending: false,
            lastActivityAtUtc: nowUtc);

        lock (_sync)
        {
            if (staged is not null) _sessions[sessionId] = staged;
        }

        _logger.LogInformation("session.exited {SessionId} exitCode={ExitCode} reason={Reason}", sessionId, exitCode, reason);
    }

    public async Task MarkReplayCompleted(string sessionId, string clientConnectionId)
    {
        SessionRecord? staged = null;
        DateTimeOffset nowUtc;

        lock (_sync)
        {
            if (!_sessions.TryGetValue(sessionId, out var session) ||
                session.AttachmentState != SessionAttachmentState.Attached ||
                session.AttachedClientConnectionId != clientConnectionId)
            {
                return;
            }
            nowUtc = _timeProvider.GetUtcNow();
            staged = session with
            {
                ReplayPending = false,
                LastActivityAtUtc = nowUtc
            };
        }

        await PersistSessionStateAsync(sessionId, "Attached",
            replayPending: false,
            lastActivityAtUtc: nowUtc);

        lock (_sync)
        {
            if (_sessions.TryGetValue(sessionId, out var current) &&
                current.AttachmentState == SessionAttachmentState.Attached &&
                current.AttachedClientConnectionId == clientConnectionId &&
                staged is not null)
            {
                _sessions[sessionId] = staged;
            }
        }
    }

    public async Task<int> RebindActiveSessions(string userId, string workerId, string workerConnectionId)
    {
        var stagedUpdates = new List<(string SessionId, SessionRecord Staged, bool WasRecovering)>();

        lock (_sync)
        {
            foreach (var (sessionId, session) in _sessions)
            {
                if (session.UserId != userId || session.WorkerId != workerId)
                {
                    continue;
                }

                if (session.AttachmentState == SessionAttachmentState.Recovering)
                {
                    stagedUpdates.Add((sessionId, session with
                    {
                        WorkerConnectionId = workerConnectionId,
                        AttachmentState = SessionAttachmentState.Attached,
                        LastActivityAtUtc = _timeProvider.GetUtcNow()
                    }, WasRecovering: true));
                    continue;
                }

                if (session.AttachmentState is not (SessionAttachmentState.Attached or SessionAttachmentState.DetachedGracePeriod) ||
                    session.WorkerConnectionId == workerConnectionId)
                {
                    continue;
                }

                stagedUpdates.Add((sessionId, session with { WorkerConnectionId = workerConnectionId }, WasRecovering: false));
            }
        }

        foreach (var (sessionId, staged, wasRecovering) in stagedUpdates)
        {
            await PersistSessionStateAsync(sessionId, "Attached",
                workerConnectionId: workerConnectionId,
                lastActivityAtUtc: staged.LastActivityAtUtc);

            if (wasRecovering)
            {
                _logger.LogInformation("Rebind: {SessionId} Recovering → Attached (worker={WorkerId})", sessionId, workerId);
            }
        }

        lock (_sync)
        {
            foreach (var (sessionId, staged, _) in stagedUpdates)
            {
                _sessions[sessionId] = staged;
            }
        }

        return stagedUpdates.Count;
    }

    public async Task<IReadOnlyList<SessionRecord>> TransitionToRecovering(string workerId, string workerConnectionId)
    {
        var stagedUpdates = new List<(string SessionId, SessionRecord Original, SessionRecord Staged)>();

        lock (_sync)
        {
            foreach (var session in _sessions.Values)
            {
                if (session.WorkerId != workerId ||
                    session.WorkerConnectionId != workerConnectionId ||
                    session.AttachmentState is not (SessionAttachmentState.Attached or SessionAttachmentState.DetachedGracePeriod))
                {
                    continue;
                }

                stagedUpdates.Add((session.SessionId, session, session with
                {
                    AttachmentState = SessionAttachmentState.Recovering,
                    WorkerConnectionId = "",
                    AttachedClientConnectionId = null,
                    LeaseExpiresAtUtc = null,
                    ReplayPending = false,
                    LastActivityAtUtc = _timeProvider.GetUtcNow()
                }));
            }
        }

        foreach (var (sessionId, _, staged) in stagedUpdates)
        {
            await PersistSessionStateAsync(sessionId, "Recovering",
                attachedClientConnectionId: null,
                workerConnectionId: "",
                leaseExpiresAtUtc: null,
                replayPending: false,
                lastActivityAtUtc: staged.LastActivityAtUtc);
            _logger.LogInformation("session.recovering {SessionId} reason=worker-disconnect worker={WorkerId}", sessionId, workerId);
        }

        lock (_sync)
        {
            foreach (var (sessionId, _, staged) in stagedUpdates)
            {
                _sessions[sessionId] = staged;
            }
        }

        return stagedUpdates.Select(u => u.Original).ToList();
    }

    public async Task<IReadOnlyList<string>> ExpireRecoveringSessions(DateTimeOffset cutoffUtc)
    {
        var stagedUpdates = new List<(string SessionId, SessionRecord Staged)>();

        lock (_sync)
        {
            foreach (var session in _sessions.Values)
            {
                if (session.AttachmentState != SessionAttachmentState.Recovering ||
                    session.LastActivityAtUtc > cutoffUtc)
                {
                    continue;
                }

                stagedUpdates.Add((session.SessionId, session with
                {
                    AttachmentState = SessionAttachmentState.Expired,
                    AttachedClientConnectionId = null,
                    LeaseExpiresAtUtc = null,
                    ExitCode = null,
                    ExitReason = "recovery-timeout",
                    ReplayPending = false,
                    LastActivityAtUtc = _timeProvider.GetUtcNow()
                }));
            }
        }

        foreach (var (sessionId, staged) in stagedUpdates)
        {
            await PersistSessionStateAsync(sessionId, "Expired",
                attachedClientConnectionId: null,
                exitCode: null,
                exitReason: "recovery-timeout",
                leaseExpiresAtUtc: null,
                replayPending: false,
                lastActivityAtUtc: staged.LastActivityAtUtc);
            _logger.LogWarning("Recovery timeout: {SessionId} Recovering → Expired (worker={WorkerId})", sessionId, staged.WorkerId);
        }

        lock (_sync)
        {
            foreach (var (sessionId, staged) in stagedUpdates)
            {
                _sessions[sessionId] = staged;
            }
        }

        if (stagedUpdates.Count > 0)
        {
            _logger.LogInformation("Expired {Count} recovering sessions due to recovery timeout", stagedUpdates.Count);
        }

        return stagedUpdates.Select(u => u.SessionId).ToList();
    }

    public bool TryGetSession(string sessionId, out SessionRecord session)
    {
        lock (_sync)
        {
            return _sessions.TryGetValue(sessionId, out session!);
        }
    }

    public bool TouchSessionActivity(string sessionId, DateTimeOffset nowUtc)
    {
        if (_lastTouchBySession.TryGetValue(sessionId, out var lastTouch) &&
            (nowUtc - lastTouch).TotalSeconds < 5.0)
        {
            return false;
        }

        _lastTouchBySession[sessionId] = nowUtc;

        lock (_sync)
        {
            if (!_sessions.TryGetValue(sessionId, out var session))
            {
                return false;
            }

            _sessions[sessionId] = session with { LastActivityAtUtc = nowUtc };
        }

        _ = TouchSessionInDbAsync(sessionId, nowUtc);

        return true;
    }

    private async Task TouchSessionInDbAsync(string sessionId, DateTimeOffset nowUtc)
    {
        await using var db = await _contextFactory.CreateDbContextAsync();
        var entity = await db.Sessions.FindAsync(sessionId);
        if (entity is not null)
        {
            entity.LastActivityAtUtc = nowUtc;
            await db.SaveChangesAsync();
        }
    }

    public async Task<RenameSessionResult> RenameSessionAsync(string userId, string sessionId, string? name)
    {
        SessionRecord? staged = null;

        lock (_sync)
        {
            if (!_sessions.TryGetValue(sessionId, out var session) || session.UserId != userId)
            {
                return RenameSessionResult.Failure("session-not-found");
            }
            staged = session with { Name = name };
        }

        await using var db = await _contextFactory.CreateDbContextAsync();
        var entity = await db.Sessions.FindAsync(sessionId);
        if (entity is not null && string.Equals(entity.UserId, userId, StringComparison.Ordinal))
        {
            entity.Name = name;
            await db.SaveChangesAsync();
        }

        lock (_sync)
        {
            if (staged is not null) _sessions[sessionId] = staged;
        }

        return RenameSessionResult.Success();
    }

    public async Task<IReadOnlyList<SessionRecord>> GetSessionsForUser(string userId)
    {
        await using var db = await _contextFactory.CreateDbContextAsync();
        var entities = await db.Sessions
            .Where(s => s.UserId == userId)
            .ToListAsync();

        return entities.Select(MapEntityToRecord).ToArray();
    }

    public async Task<IReadOnlyList<SessionRecord>> GetAllActiveSessions()
    {
        await using var db = await _contextFactory.CreateDbContextAsync();
        var entities = await db.Sessions
            .Where(s => s.AttachmentState == "Attached" || s.AttachmentState == "DetachedGracePeriod")
            .ToListAsync();

        return entities.Select(MapEntityToRecord).ToArray();
    }

    private static SessionRecord MapEntityToRecord(SessionRecordEntity entity)
    {
        var state = Enum.TryParse<SessionAttachmentState>(entity.AttachmentState, ignoreCase: false, out var parsed)
            ? parsed
            : SessionAttachmentState.Attached;

        return new SessionRecord(
            entity.SessionId,
            entity.UserId,
            entity.WorkerId,
            entity.WorkerConnectionId ?? "",
            entity.Columns,
            entity.Rows,
            entity.CreatedAtUtc,
            entity.LastActivityAtUtc,
            state,
            entity.AttachedClientConnectionId,
            entity.LeaseExpiresAtUtc,
            entity.ExitCode,
            entity.ExitReason,
            entity.ReplayPending,
            entity.Name);
    }

    private async Task PersistSessionStateAsync(
        string sessionId,
        string attachmentState,
        string? attachedClientConnectionId = null,
        string? workerConnectionId = null,
        DateTimeOffset? leaseExpiresAtUtc = null,
        int? exitCode = null,
        string? exitReason = null,
        bool? replayPending = null,
        DateTimeOffset? lastActivityAtUtc = null,
        string? name = null,
        CancellationToken cancellationToken = default)
    {
        await using var db = await _contextFactory.CreateDbContextAsync(cancellationToken);
        var entity = await db.Sessions.FindAsync(sessionId, cancellationToken);
        if (entity is null) return;

        entity.AttachmentState = attachmentState;
        entity.AttachedClientConnectionId = attachedClientConnectionId;
        if (workerConnectionId is not null)
            entity.WorkerConnectionId = workerConnectionId;
        entity.LeaseExpiresAtUtc = leaseExpiresAtUtc;
        entity.ExitCode = exitCode;
        entity.ExitReason = exitReason;
        if (lastActivityAtUtc.HasValue)
            entity.LastActivityAtUtc = lastActivityAtUtc.Value;
        if (replayPending.HasValue)
            entity.ReplayPending = replayPending.Value;
        if (name is not null)
            entity.Name = name;
        await db.SaveChangesAsync(cancellationToken);
    }
}
