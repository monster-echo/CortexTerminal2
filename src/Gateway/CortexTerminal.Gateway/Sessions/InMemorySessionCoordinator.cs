using System.Collections.Concurrent;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Workers;

namespace CortexTerminal.Gateway.Sessions;

public sealed class InMemorySessionCoordinator : ISessionCoordinator
{
    private readonly IWorkerRegistry _workers;
    private readonly ConcurrentDictionary<string, SessionRecord> _sessions = new();
    private readonly object _sync = new();
    private readonly TimeProvider _timeProvider;

    public InMemorySessionCoordinator(IWorkerRegistry workers, TimeProvider? timeProvider = null)
    {
        _workers = workers;
        _timeProvider = timeProvider ?? TimeProvider.System;
    }

    public Task<CreateSessionResult> CreateSessionAsync(string userId, CreateSessionRequest request, string? clientConnectionId, CancellationToken cancellationToken)
    {
        if (!_workers.TryGetLeastBusyForUser(userId, out var worker))
        {
            return Task.FromResult(CreateSessionResult.Failure("no-worker-available"));
        }

        _workers.SetWorkerOwner(worker.WorkerId, userId);
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
        }

        return Task.CompletedTask;
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
                return Task.FromResult(ReattachSessionResult.Failure("session-already-attached"));
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

    public IReadOnlyList<SessionRecord> GetSessionsForUser(string userId)
    {
        lock (_sync)
        {
            return _sessions.Values.Where(session => session.UserId == userId).ToArray();
        }
    }
}
