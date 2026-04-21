using CortexTerminal.Contracts.Sessions;

namespace CortexTerminal.Gateway.Sessions;

public interface ISessionCoordinator
{
    Task<CreateSessionResult> CreateSessionAsync(string userId, CreateSessionRequest request, string? clientConnectionId, CancellationToken cancellationToken);
    Task DetachSessionAsync(string userId, string sessionId, DateTimeOffset detachedAtUtc, CancellationToken cancellationToken);
    Task<ReattachSessionResult> ReattachSessionAsync(string userId, ReattachSessionRequest request, string clientConnectionId, DateTimeOffset nowUtc, CancellationToken cancellationToken);
    void MarkReplayCompleted(string sessionId, string clientConnectionId);
    IReadOnlyList<string> ExpireDetachedSessions(DateTimeOffset nowUtc);
    bool TryGetSession(string sessionId, out SessionRecord session);
}
