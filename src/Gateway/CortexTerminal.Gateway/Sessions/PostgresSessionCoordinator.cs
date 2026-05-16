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

    public PostgresSessionCoordinator(
        IWorkerRegistry workers,
        IServiceScopeFactory scopeFactory,
        TimeProvider? timeProvider = null)
    {
        _workers = workers;
        _scopeFactory = scopeFactory;
        _timeProvider = timeProvider ?? TimeProvider.System;
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
        });

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

            _sessions[sessionId] = session with
            {
                AttachmentState = SessionAttachmentState.DetachedGracePeriod,
                AttachedClientConnectionId = null,
                LeaseExpiresAtUtc = detachedAtUtc.AddMinutes(5),
                ReplayPending = false,
                LastActivityAtUtc = detachedAtUtc
            };

            PersistSessionState(sessionId, "DetachedGracePeriod",
                attachedClientConnectionId: null,
                leaseExpiresAtUtc: detachedAtUtc.AddMinutes(5));
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

            if (session.AttachmentState is SessionAttachmentState.Attached or SessionAttachmentState.DetachedGracePeriod)
            {
                return Task.FromResult(DeleteSessionResult.Failure("session-running"));
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
        });

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
    }

    public void RemoveSession(string sessionId)
    {
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
        });
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
                if (session.UserId != userId ||
                    session.WorkerId != workerId ||
                    session.AttachmentState is not (SessionAttachmentState.Attached or SessionAttachmentState.DetachedGracePeriod) ||
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

    public IReadOnlyList<SessionRecord> ExpireSessionsForWorkerConnection(string workerId, string workerConnectionId)
    {
        var expiredSessions = new List<SessionRecord>();

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

                expiredSessions.Add(session);

                _sessions[session.SessionId] = session with
                {
                    AttachmentState = SessionAttachmentState.Expired,
                    AttachedClientConnectionId = null,
                    LeaseExpiresAtUtc = null,
                    ExitCode = null,
                    ExitReason = "worker-offline",
                    ReplayPending = false,
                    LastActivityAtUtc = _timeProvider.GetUtcNow()
                };

                PersistSessionState(session.SessionId, "Expired", exitReason: "worker-offline");
            }
        }

        return expiredSessions;
    }

    public IReadOnlyList<string> ExpireDetachedSessions(DateTimeOffset nowUtc)
    {
        var expiredSessionIds = new List<string>();

        lock (_sync)
        {
            foreach (var session in _sessions.Values)
            {
                if (session.AttachmentState != SessionAttachmentState.DetachedGracePeriod ||
                    !session.LeaseExpiresAtUtc.HasValue ||
                    session.LeaseExpiresAtUtc.Value > nowUtc)
                {
                    continue;
                }

                _sessions[session.SessionId] = session with
                {
                    AttachmentState = SessionAttachmentState.Expired,
                    AttachedClientConnectionId = null,
                    LeaseExpiresAtUtc = null,
                    ExitCode = null,
                    ExitReason = "expired",
                    ReplayPending = false,
                    LastActivityAtUtc = nowUtc
                };
                expiredSessionIds.Add(session.SessionId);

                PersistSessionState(session.SessionId, "Expired", exitReason: "expired");
            }
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
        });

        return true;
    }

    public IReadOnlyList<SessionRecord> GetSessionsForUser(string userId)
    {
        lock (_sync)
        {
            return _sessions.Values.Where(session => session.UserId == userId).ToArray();
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
        });
    }

    private async Task PersistAsync(Func<AppDbContext, Task> action)
    {
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            await action(db);
            await db.SaveChangesAsync();
        }
        catch
        {
            // DB persistence failure should not block real-time operations
        }
    }
}
