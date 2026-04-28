using CortexTerminal.Contracts.Sessions;

namespace CortexTerminal.Gateway.Sessions;

public interface ISessionLaunchCoordinator
{
    Task<CreateSessionResult> CreateSessionAsync(string userId, CreateSessionRequest request, string? clientConnectionId, CancellationToken cancellationToken);
}