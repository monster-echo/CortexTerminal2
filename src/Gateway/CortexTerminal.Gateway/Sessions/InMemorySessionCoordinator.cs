using System.Collections.Concurrent;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Workers;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Gateway.Sessions;

public sealed class InMemorySessionCoordinator : ISessionCoordinator
{
    private readonly IWorkerRegistry _workers;
    private readonly ConcurrentDictionary<string, SessionRecord> _sessions = new();
    private readonly ConcurrentDictionary<string, DateTimeOffset> _lastTouchBySession = new();
    private readonly object _sync = new();
    private readonly TimeProvider _timeProvider;
    private readonly ILogger<InMemorySessionCoordinator> _logger;

    public InMemorySessionCoordinator(IWorkerRegistry workers, ILogger<InMemorySessionCoordinator> logger, TimeProvider? timeProvider = null)
    {
        _workers = workers;
        _logger = logger;
        _timeProvider = timeProvider ?? TimeProvider.System;
    }

    public Task RecoverActiveSessionsAsync() => Task.CompletedTask;

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
            _sessions[sessionId] = session with
            {
                AttachedClientConnectionId = null,
                ReplayPending = false,
                LastActivityAtUtc = detachedAtUtc
            };
        }

        _logger.LogInformation("session.client-detached {SessionId} user={UserId}", sessionId, userId);

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

            _sessions.TryRemove(sessionId, out _);
        }

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
                if (session.AttachedClientConnectionId is null)
                {
                    _sessions[request.SessionId] = session with
                    {
                        AttachedClientConnectionId = clientConnectionId,
                        LeaseExpiresAtUtc = null,
                        ReplayPending = true,
                        LastActivityAtUtc = nowUtc
                    };

                    _logger.LogInformation("session.reattached {SessionId} client={ClientConnectionId}", request.SessionId, clientConnectionId);

                    return Task.FromResult(ReattachSessionResult.Success());
                }

                _sessions[request.SessionId] = session with
                {
                    AttachedClientConnectionId = clientConnectionId,
                    LeaseExpiresAtUtc = null,
                    ReplayPending = true,
                    LastActivityAtUtc = nowUtc
                };

                _logger.LogInformation("session.reattached {SessionId} client={ClientConnectionId} (displaced existing)", request.SessionId, clientConnectionId);

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

                _logger.LogInformation("session.expired {SessionId} reason=detached-without-lease", request.SessionId);

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

                _logger.LogInformation("session.expired {SessionId} reason=lease-expired", request.SessionId);

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
        }
    }

    public int RebindActiveSessions(string userId, string workerId, string workerConnectionId)
    {
        var reboundCount = 0;

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
                reboundCount++;
                _logger.LogInformation("session.rebound {SessionId} worker={WorkerId}", sessionId, workerId);
            }
        }

        return reboundCount;
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

                _logger.LogInformation("session.expired {SessionId} reason=worker-offline worker={WorkerId}", session.SessionId, workerId);
            }
        }

        return expiredSessions;
    }

    public IReadOnlyList<string> ExpireDetachedSessions(DateTimeOffset nowUtc)
    {
        // No-op: sessions are no longer expired due to client disconnect.
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

                _logger.LogInformation("session.expired {SessionId} reason=recovery-timeout worker={WorkerId}", session.SessionId, session.WorkerId);
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
}
