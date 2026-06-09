using CortexTerminal.Contracts.Sessions;

namespace CortexTerminal.Gateway.Sessions;

public interface ISessionCoordinator
{
    Task RecoverActiveSessionsAsync();
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
    IReadOnlyList<string> ExpireRecoveringSessions(DateTimeOffset cutoffUtc);
    bool TryGetSession(string sessionId, out SessionRecord session);
    bool TouchSessionActivity(string sessionId, DateTimeOffset nowUtc);
    RenameSessionResult RenameSessionAsync(string userId, string sessionId, string? name);
}
