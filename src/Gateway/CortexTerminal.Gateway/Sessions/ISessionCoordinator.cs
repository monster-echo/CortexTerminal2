using CortexTerminal.Contracts.Sessions;

namespace CortexTerminal.Gateway.Sessions;

public interface ISessionCoordinator
{
    Task RecoverActiveSessionsAsync();
    Task<CreateSessionResult> CreateSessionAsync(string userId, CreateSessionRequest request, string? clientConnectionId, CancellationToken cancellationToken);
    Task DetachSessionAsync(string userId, string sessionId, DateTimeOffset detachedAtUtc, CancellationToken cancellationToken);
    Task<DeleteSessionResult> DeleteSessionAsync(string userId, string sessionId, CancellationToken cancellationToken);
    Task<ReattachSessionResult> ReattachSessionAsync(string userId, ReattachSessionRequest request, string clientConnectionId, DateTimeOffset nowUtc, CancellationToken cancellationToken);
    Task<IReadOnlyList<SessionRecord>> GetSessionsForUser(string userId);
    Task MarkSessionStartFailed(string sessionId, string reason);
    Task MarkSessionExited(string sessionId, int exitCode, string reason);
    Task RemoveSession(string sessionId);
    Task MarkReplayCompleted(string sessionId, string clientConnectionId);
    Task<int> RebindActiveSessions(string userId, string workerId, string workerConnectionId);
    Task<IReadOnlyList<SessionRecord>> TransitionToRecovering(string workerId, string workerConnectionId);
    Task<IReadOnlyList<string>> ReconcileWorkerSessionsAsync(string userId, string workerId, IReadOnlySet<string> liveSessionIds);
    bool TryGetSession(string sessionId, out SessionRecord session);
    bool TouchSessionActivity(string sessionId, DateTimeOffset nowUtc);
    Task<RenameSessionResult> RenameSessionAsync(string userId, string sessionId, string? name);
    Task<IReadOnlyList<SessionRecord>> GetAllActiveSessions();
}
