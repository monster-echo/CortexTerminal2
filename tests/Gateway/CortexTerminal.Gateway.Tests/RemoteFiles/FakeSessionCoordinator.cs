using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Sessions;

namespace CortexTerminal.Gateway.Tests.RemoteFiles;

/// <summary>
/// Single-session ISessionCoordinator double: only TryGetSession is functional; every other
/// member throws so a test that accidentally reaches coordinator mutations fails loudly.
/// </summary>
internal sealed class FakeSessionCoordinator(SessionRecord? session) : ISessionCoordinator
{
    public bool TryGetSession(string sessionId, out SessionRecord record)
    {
        if (session is not null && session.SessionId == sessionId)
        {
            record = session;
            return true;
        }
        record = null!;
        return false;
    }

    public Task RecoverActiveSessionsAsync() => throw new NotSupportedException();
    public Task<CreateSessionResult> CreateSessionAsync(string userId, CreateSessionRequest request, string? clientConnectionId, CancellationToken cancellationToken) => throw new NotSupportedException();
    public Task DetachSessionAsync(string userId, string sessionId, DateTimeOffset detachedAtUtc, CancellationToken cancellationToken) => throw new NotSupportedException();
    public Task<DeleteSessionResult> DeleteSessionAsync(string userId, string sessionId, CancellationToken cancellationToken) => throw new NotSupportedException();
    public Task<ReattachSessionResult> ReattachSessionAsync(string userId, ReattachSessionRequest request, string clientConnectionId, DateTimeOffset nowUtc, CancellationToken cancellationToken) => throw new NotSupportedException();
    public Task<IReadOnlyList<SessionRecord>> GetSessionsForUser(string userId) => throw new NotSupportedException();
    public Task MarkSessionStartFailed(string sessionId, string reason) => throw new NotSupportedException();
    public Task MarkSessionExited(string sessionId, int exitCode, string reason) => throw new NotSupportedException();
    public Task RemoveSession(string sessionId) => throw new NotSupportedException();
    public Task MarkReplayCompleted(string sessionId, string clientConnectionId) => throw new NotSupportedException();
    public Task<int> RebindActiveSessions(string userId, string workerId, string workerConnectionId) => throw new NotSupportedException();
    public Task<IReadOnlyList<SessionRecord>> TransitionToRecovering(string workerId, string workerConnectionId) => throw new NotSupportedException();
    public Task<IReadOnlyList<string>> ReconcileWorkerSessionsAsync(string userId, string workerId, IReadOnlySet<string> liveSessionIds) => throw new NotSupportedException();
    public bool TouchSessionActivity(string sessionId, DateTimeOffset nowUtc) => throw new NotSupportedException();
    public Task<RenameSessionResult> RenameSessionAsync(string userId, string sessionId, string? name) => throw new NotSupportedException();
    public Task<IReadOnlyList<SessionRecord>> GetAllActiveSessions() => throw new NotSupportedException();
}
