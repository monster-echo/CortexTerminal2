using System.Collections.Concurrent;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Workers;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace CortexTerminal.Gateway.Sessions;

public sealed class PostgresSessionCoordinator : ISessionCoordinator
{
    private readonly IWorkerRegistry _workers;
    private readonly ConcurrentDictionary<string, SessionRecord> _sessions = new();
    private readonly ConcurrentDictionary<string, DateTimeOffset> _lastTouchBySession = new();
    private readonly object _sync = new();
    private readonly TimeProvider _timeProvider;
    private readonly IServiceScopeFactory _scopeFactory;

    private readonly ILogger<PostgresSessionCoordinator> _logger;

    public PostgresSessionCoordinator(
        IWorkerRegistry workers,
        IServiceScopeFactory scopeFactory,
        ILogger<PostgresSessionCoordinator> logger,
        TimeProvider? timeProvider = null)
    {
        _workers = workers;
        _scopeFactory = scopeFactory;
        _logger = logger;
        _timeProvider = timeProvider ?? TimeProvider.System;
    }

    public async Task RecoverActiveSessionsAsync()
    {
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

            var recoverableStates = new[] { "Attached", "DetachedGracePeriod" };
            var entities = await db.Sessions
                .Where(e => recoverableStates.Contains(e.AttachmentState))
                .ToListAsync();

            if (entities.Count == 0) return;

            var now = _timeProvider.GetUtcNow();

            lock (_sync)
            {
                foreach (var entity in entities)
                {
                    var record = new SessionRecord(
                        entity.SessionId,
                        entity.UserId,
                        entity.WorkerId,
                        WorkerConnectionId: "",
                        entity.Columns,
                        entity.Rows,
                        entity.CreatedAtUtc,
                        LastActivityAtUtc: now,
                        AttachmentState: SessionAttachmentState.Recovering,
                        AttachedClientConnectionId: null,
                        LeaseExpiresAtUtc: null,
                        Name: entity.Name);

                    _sessions[entity.SessionId] = record;
                    _logger.LogInformation("session.recovering {SessionId} worker={WorkerId} user={UserId}", entity.SessionId, entity.WorkerId, entity.UserId);
                }
            }

            _ = PersistAsync(async db =>
            {
                foreach (var entity in entities)
                {
                    var tracked = await db.Sessions.FindAsync(entity.SessionId);
                    if (tracked is not null)
                    {
                        tracked.AttachmentState = "Recovering";
                        tracked.AttachedClientConnectionId = null;
                    }
                }
            }, $"RecoverActiveSessions:{entities.Count}");

            _logger.LogInformation("Recovered {Count} active sessions from database", entities.Count);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to recover sessions from database");
        }
    }

    public Task<CreateSessionResult> CreateSessionAsync(string userId, CreateSessionRequest request, string? clientConnectionId, CancellationToken cancellationToken)
    {
        RegisteredWorker worker;

        if (!string.IsNullOrEmpty(request.WorkerId))
        {
            if (!_workers.TryGetWorker(request.WorkerId, out var requested) ||
                (requested.OwnerUserId is not null && requested.OwnerUserId != userId))
            {
                return Task.FromResult(CreateSessionResult.Failure("worker-not-found"));
            }
            worker = requested;
        }
        else
        {
            if (!_workers.TryGetLeastBusyForUser(userId, out var leastBusy))
            {
                return Task.FromResult(CreateSessionResult.Failure("no-worker-available"));
            }
            worker = leastBusy;
        }

        if (!_workers.SetWorkerOwner(worker.WorkerId, userId))
        {
            return Task.FromResult(CreateSessionResult.Failure("no-worker-available"));
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

        lock (_sync)
        {
            _sessions[sessionId] = record;
        }

        _ = PersistAsync(async db =>
        {
            db.Sessions.Add(new SessionRecordEntity
            {
                SessionId = sessionId,
                UserId = userId,
                WorkerId = worker.WorkerId,
                Columns = request.Columns,
                Rows = request.Rows,
                CreatedAtUtc = now,
                LastActivityAtUtc = now,
                AttachmentState = "Attached",
                AttachedClientConnectionId = clientConnectionId
            });
        }, $"CreateSession:{sessionId}");

        _logger.LogInformation("session.created {SessionId} worker={WorkerId} user={UserId}", sessionId, worker.WorkerId, userId);

        return Task.FromResult(CreateSessionResult.Success(new CreateSessionResponse(sessionId, worker.WorkerId)));
    }

    public Task DetachSessionAsync(string userId, string sessionId, DateTimeOffset detachedAtUtc, CancellationToken cancellationToken)
    {
        lock (_sync)
        {
            if (!_sessions.TryGetValue(sessionId, out var session) || session.UserId != userId)
            {
                return Task.CompletedTask;
            }

            // Session stays Attached — only clear the client connection.
            // The session remains alive as long as the Worker/PTY is running.
            // Client can Reattach at any time.
            _sessions[sessionId] = session with
            {
                AttachedClientConnectionId = null,
                ReplayPending = false,
                LastActivityAtUtc = detachedAtUtc
            };

            PersistSessionState(sessionId, "Attached",
                attachedClientConnectionId: null);

            _logger.LogInformation("session.client-detached {SessionId} user={UserId}", sessionId, userId);
        }

        return Task.CompletedTask;
    }

    public Task<DeleteSessionResult> DeleteSessionAsync(string userId, string sessionId, CancellationToken cancellationToken)
    {
        lock (_sync)
        {
            if (!_sessions.TryGetValue(sessionId, out var session) || session.UserId != userId)
            {
                return Task.FromResult(DeleteSessionResult.Failure("session-not-found"));
            }
        }

        lock (_sync)
        {
            _sessions.TryRemove(sessionId, out _);
        }

        _ = PersistAsync(async db =>
        {
            var entity = await db.Sessions.FindAsync(sessionId);
            if (entity is not null && string.Equals(entity.UserId, userId, StringComparison.Ordinal))
            {
                db.Sessions.Remove(entity);
            }
        }, $"DeleteSession:{sessionId}");

        _logger.LogInformation("session.deleted {SessionId} user={UserId}", sessionId, userId);

        return Task.FromResult(DeleteSessionResult.Success());
    }

    public Task<ReattachSessionResult> ReattachSessionAsync(
        string userId,
        ReattachSessionRequest request,
        string clientConnectionId,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        lock (_sync)
        {
            if (!_sessions.TryGetValue(request.SessionId, out var session) || session.UserId != userId)
            {
                return Task.FromResult(ReattachSessionResult.Failure("session-not-found"));
            }

            if (session.AttachmentState == SessionAttachmentState.Attached)
            {
                _sessions[request.SessionId] = session with
                {
                    AttachedClientConnectionId = clientConnectionId,
                    LeaseExpiresAtUtc = null,
                    ReplayPending = true,
                    LastActivityAtUtc = nowUtc
                };

                PersistSessionState(request.SessionId, "Attached",
                    attachedClientConnectionId: clientConnectionId,
                    replayPending: true);

                _logger.LogInformation("session.reattached {SessionId} client={ClientConnectionId} (displaced existing)", request.SessionId, clientConnectionId);

                return Task.FromResult(ReattachSessionResult.Success());
            }

            if (session.AttachmentState == SessionAttachmentState.Recovering)
            {
                _sessions[request.SessionId] = session with
                {
                    AttachmentState = SessionAttachmentState.Attached,
                    AttachedClientConnectionId = clientConnectionId,
                    LeaseExpiresAtUtc = null,
                    ReplayPending = false,
                    LastActivityAtUtc = nowUtc
                };

                PersistSessionState(request.SessionId, "Attached",
                    attachedClientConnectionId: clientConnectionId);

                _logger.LogInformation("Reattach: {SessionId} Recovering → Attached (client={ClientConnectionId})", request.SessionId, clientConnectionId);

                return Task.FromResult(ReattachSessionResult.Success());
            }

            if (session.AttachmentState != SessionAttachmentState.DetachedGracePeriod)
            {
                return Task.FromResult(ReattachSessionResult.Failure("session-expired"));
            }

            if (!session.LeaseExpiresAtUtc.HasValue)
            {
                _sessions[request.SessionId] = session with
                {
                    AttachmentState = SessionAttachmentState.Expired,
                    AttachedClientConnectionId = null,
                    LeaseExpiresAtUtc = null,
                    ReplayPending = false,
                    LastActivityAtUtc = nowUtc
                };

                PersistSessionState(request.SessionId, "Expired");

                return Task.FromResult(ReattachSessionResult.Failure("session-detached-without-lease"));
            }

            if (session.LeaseExpiresAtUtc.Value <= nowUtc)
            {
                _sessions[request.SessionId] = session with
                {
                    AttachmentState = SessionAttachmentState.Expired,
                    AttachedClientConnectionId = null,
                    LeaseExpiresAtUtc = null,
                    ReplayPending = false,
                    LastActivityAtUtc = nowUtc
                };

                PersistSessionState(request.SessionId, "Expired");

                return Task.FromResult(ReattachSessionResult.Failure("session-expired"));
            }

            _sessions[request.SessionId] = session with
            {
                AttachmentState = SessionAttachmentState.Attached,
                AttachedClientConnectionId = clientConnectionId,
                LeaseExpiresAtUtc = null,
                ReplayPending = true,
                LastActivityAtUtc = nowUtc
            };

            PersistSessionState(request.SessionId, "Attached",
                attachedClientConnectionId: clientConnectionId,
                replayPending: true);

            _logger.LogInformation("session.reattached {SessionId} client={ClientConnectionId} (from DetachedGracePeriod)", request.SessionId, clientConnectionId);

            return Task.FromResult(ReattachSessionResult.Success());
        }
    }

    public void MarkSessionStartFailed(string sessionId, string reason)
    {
        lock (_sync)
        {
            if (!_sessions.TryGetValue(sessionId, out var session))
            {
                return;
            }

            _sessions[sessionId] = session with
            {
                AttachmentState = SessionAttachmentState.Exited,
                AttachedClientConnectionId = null,
                ExitCode = null,
                ExitReason = reason,
                ReplayPending = false,
                LeaseExpiresAtUtc = null,
                LastActivityAtUtc = _timeProvider.GetUtcNow()
            };

            PersistSessionState(sessionId, "Exited", exitReason: reason);
        }

        _logger.LogInformation("session.start-failed {SessionId} reason={Reason}", sessionId, reason);
    }

    public void RemoveSession(string sessionId)
    {
        _logger.LogInformation("session.removed {SessionId}", sessionId);

        lock (_sync)
        {
            _sessions.TryRemove(sessionId, out _);
        }

        _lastTouchBySession.TryRemove(sessionId, out _);

        _ = PersistAsync(async db =>
        {
            var entity = await db.Sessions.FindAsync(sessionId);
            if (entity is not null)
            {
                db.Sessions.Remove(entity);
            }
        }, $"RemoveSession:{sessionId}");
    }

    public void MarkSessionExited(string sessionId, int exitCode, string reason)
    {
        lock (_sync)
        {
            if (!_sessions.TryGetValue(sessionId, out var session))
            {
                return;
            }

            _sessions[sessionId] = session with
            {
                AttachmentState = SessionAttachmentState.Exited,
                AttachedClientConnectionId = null,
                ExitCode = exitCode,
                ExitReason = reason,
                ReplayPending = false,
                LeaseExpiresAtUtc = null,
                LastActivityAtUtc = _timeProvider.GetUtcNow()
            };

            PersistSessionState(sessionId, "Exited", exitCode: exitCode, exitReason: reason);
        }

        _logger.LogInformation("session.exited {SessionId} exitCode={ExitCode} reason={Reason}", sessionId, exitCode, reason);
    }

    public void MarkReplayCompleted(string sessionId, string clientConnectionId)
    {
        lock (_sync)
        {
            if (!_sessions.TryGetValue(sessionId, out var session) ||
                session.AttachmentState != SessionAttachmentState.Attached ||
                session.AttachedClientConnectionId != clientConnectionId)
            {
                return;
            }

            _sessions[sessionId] = session with
            {
                ReplayPending = false,
                LastActivityAtUtc = _timeProvider.GetUtcNow()
            };

            PersistSessionState(sessionId, "Attached", replayPending: false);
        }
    }

    public int RebindActiveSessions(string userId, string workerId, string workerConnectionId)
    {
        var reboundSessionIds = new List<string>();

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
                    _sessions[sessionId] = session with
                    {
                        WorkerConnectionId = workerConnectionId,
                        AttachmentState = SessionAttachmentState.Attached,
                        LastActivityAtUtc = _timeProvider.GetUtcNow()
                    };
                    reboundSessionIds.Add(sessionId);
                    PersistSessionState(sessionId, "Attached");
                    _logger.LogInformation("Rebind: {SessionId} Recovering → Attached (worker={WorkerId})", sessionId, workerId);
                    continue;
                }

                if (session.AttachmentState is not (SessionAttachmentState.Attached or SessionAttachmentState.DetachedGracePeriod) ||
                    session.WorkerConnectionId == workerConnectionId)
                {
                    continue;
                }

                _sessions[sessionId] = session with { WorkerConnectionId = workerConnectionId };
                reboundSessionIds.Add(sessionId);
            }
        }

        return reboundSessionIds.Count;
    }

    public IReadOnlyList<SessionRecord> TransitionToRecovering(string workerId, string workerConnectionId)
    {
        var transitionedSessions = new List<SessionRecord>();

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

                transitionedSessions.Add(session);

                _sessions[session.SessionId] = session with
                {
                    AttachmentState = SessionAttachmentState.Recovering,
                    WorkerConnectionId = "",
                    AttachedClientConnectionId = null,
                    LeaseExpiresAtUtc = null,
                    ReplayPending = false,
                    LastActivityAtUtc = _timeProvider.GetUtcNow()
                };

                PersistSessionState(session.SessionId, "Recovering",
                    attachedClientConnectionId: null);
                _logger.LogInformation("session.recovering {SessionId} reason=worker-disconnect worker={WorkerId}", session.SessionId, workerId);
            }
        }

        return transitionedSessions;
    }

    public IReadOnlyList<string> ExpireDetachedSessions(DateTimeOffset nowUtc)
    {
        // No-op: sessions are no longer expired due to client disconnect.
        // Only Worker offline or process exit terminates a session.
        return [];
    }

    public IReadOnlyList<string> ExpireRecoveringSessions(DateTimeOffset cutoffUtc)
    {
        var expiredSessionIds = new List<string>();

        lock (_sync)
        {
            foreach (var session in _sessions.Values)
            {
                if (session.AttachmentState != SessionAttachmentState.Recovering ||
                    session.LastActivityAtUtc > cutoffUtc)
                {
                    continue;
                }

                _sessions[session.SessionId] = session with
                {
                    AttachmentState = SessionAttachmentState.Expired,
                    AttachedClientConnectionId = null,
                    LeaseExpiresAtUtc = null,
                    ExitCode = null,
                    ExitReason = "recovery-timeout",
                    ReplayPending = false,
                    LastActivityAtUtc = _timeProvider.GetUtcNow()
                };
                expiredSessionIds.Add(session.SessionId);

                PersistSessionState(session.SessionId, "Expired", exitReason: "recovery-timeout");
                _logger.LogWarning("Recovery timeout: {SessionId} Recovering → Expired (worker={WorkerId})", session.SessionId, session.WorkerId);
            }
        }

        if (expiredSessionIds.Count > 0)
        {
            _logger.LogInformation("Expired {Count} recovering sessions due to recovery timeout", expiredSessionIds.Count);
        }

        return expiredSessionIds;
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

        _ = PersistAsync(async db =>
        {
            var entity = await db.Sessions.FindAsync(sessionId);
            if (entity is not null)
            {
                entity.LastActivityAtUtc = nowUtc;
            }
        }, $"TouchSessionActivity:{sessionId}");

        return true;
    }

    public RenameSessionResult RenameSessionAsync(string userId, string sessionId, string? name)
    {
        lock (_sync)
        {
            if (!_sessions.TryGetValue(sessionId, out var session) || session.UserId != userId)
            {
                return RenameSessionResult.Failure("session-not-found");
            }

            _sessions[sessionId] = session with { Name = name };
        }

        _ = PersistAsync(async db =>
        {
            var entity = await db.Sessions.FindAsync(sessionId);
            if (entity is not null)
            {
                entity.Name = name;
            }
        }, $"RenameSession:{sessionId}");

        return RenameSessionResult.Success();
    }

    public IReadOnlyList<SessionRecord> GetSessionsForUser(string userId)
    {
        lock (_sync)
        {
            return _sessions.Values.Where(session => session.UserId == userId).ToArray();
        }
    }

    public (int Active, int Detached) GetAllSessionCounts()
    {
        lock (_sync)
        {
            var active = 0;
            var detached = 0;
            foreach (var session in _sessions.Values)
            {
                if (session.AttachmentState == SessionAttachmentState.Attached) active++;
                else if (session.AttachmentState == SessionAttachmentState.DetachedGracePeriod) detached++;
            }
            return (active, detached);
        }
    }

    public IReadOnlyList<SessionRecord> GetAllActiveSessions()
    {
        lock (_sync)
        {
            return _sessions.Values
                .Where(s => s.AttachmentState is SessionAttachmentState.Attached or SessionAttachmentState.DetachedGracePeriod)
                .ToArray();
        }
    }

    private void PersistSessionState(
        string sessionId,
        string attachmentState,
        string? attachedClientConnectionId = null,
        DateTimeOffset? leaseExpiresAtUtc = null,
        int? exitCode = null,
        string? exitReason = null,
        bool? replayPending = null)
    {
        _ = PersistAsync(async db =>
        {
            var entity = await db.Sessions.FindAsync(sessionId);
            if (entity is null) return;

            entity.AttachmentState = attachmentState;
            entity.AttachedClientConnectionId = attachedClientConnectionId;
            entity.LeaseExpiresAtUtc = leaseExpiresAtUtc;
            entity.ExitCode = exitCode;
            entity.ExitReason = exitReason;
            entity.LastActivityAtUtc = _timeProvider.GetUtcNow();
            if (replayPending.HasValue)
                entity.ReplayPending = replayPending.Value;
        }, $"PersistSessionState:{attachmentState}:{sessionId}");
    }

    private async Task PersistAsync(Func<AppDbContext, Task> action, string operation)
    {
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            await action(db);
            await db.SaveChangesAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "session.persistence-failed {Operation}", operation);
        }
    }
}
