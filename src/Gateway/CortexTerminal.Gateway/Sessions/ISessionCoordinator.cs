using CortexTerminal.Contracts.Sessions;

namespace CortexTerminal.Gateway.Sessions;

public interface ISessionCoordinator
{
    Task<CreateSessionResult> CreateSessionAsync(string userId, CreateSessionRequest request, CancellationToken cancellationToken);
    bool TryGetSession(string sessionId, out SessionRecord session);
}
