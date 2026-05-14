using CortexTerminal.Contracts.Sessions;

namespace CortexTerminal.Gateway.Sessions;

public interface ISessionCoordinator
{
    Task<CreateSessionResult> CreateSessionAsync(string userId, CreateSessionRequest request, string? clientConnectionId, CancellationToken cancellationToken);
    Task DetachSessionAsync(string userId, string sessionId, DateTimeOffset detachedAtUtc, CancellationToken cancellationToken);
    Task<DeleteSessionResult> DeleteSessionAsync(string userId, string sessionId, CancellationToken cancellationToken);
    Task<ReattachSessionResult> ReattachSessionAsync(string userId, ReattachSessionRequest request, string clientConnectionId, DateTimeOffset nowUtc, CancellationToken cancellationToken);
    IReadOnlyList<SessionRecord> GetSessionsForUser(string userId);
    void MarkSessionStartFailed(string sessionId, string reason);
    void MarkSessionExited(string sessionId, int exitCode, string reason);
    void RemoveSession(string sessionId);
    void MarkReplayCompleted(string sessionId, string clientConnectionId);
    int RebindActiveSessions(string userId, string workerId, string workerConnectionId);
    IReadOnlyList<SessionRecord> ExpireSessionsForWorkerConnection(string workerId, string workerConnectionId);
    IReadOnlyList<string> ExpireDetachedSessions(DateTimeOffset nowUtc);
    bool TryGetSession(string sessionId, out SessionRecord session);
}
