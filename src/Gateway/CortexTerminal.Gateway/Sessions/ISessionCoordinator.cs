using CortexTerminal.Contracts.Sessions;

namespace CortexTerminal.Gateway.Sessions;

public interface ISessionCoordinator
{
    Task RecoverActiveSessionsAsync();
    Task<CreateSessionResult> CreateSessionAsync(string userId, CreateSessionRequest request, string? clientConnectionId, CancellationToken cancellationToken);
    Task DetachSessionAsync(string userId, string sessionId, DateTimeOffset detachedAtUtc, CancellationToken cancellationToken, string? clientConnectionId = null);
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
    bool TryRebindSessionWorkerConnection(string sessionId, string workerConnectionId);
    bool TouchSessionActivity(string sessionId, DateTimeOffset nowUtc);
    Task<RenameSessionResult> RenameSessionAsync(string userId, string sessionId, string? name);

    /// <summary>把会话移入工作区（workspaceId 为 null = 移出为未分组）。返回是否成功。</summary>
    Task<bool> MoveSessionWorkspaceAsync(string userId, string sessionId, string? workspaceId);
    Task<IReadOnlyList<SessionRecord>> GetAllActiveSessions();
}
