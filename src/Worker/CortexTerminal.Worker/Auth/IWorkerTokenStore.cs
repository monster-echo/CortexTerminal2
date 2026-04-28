namespace CortexTerminal.Worker.Auth;

public interface IWorkerTokenStore
{
    Task<string?> GetAccessTokenAsync(CancellationToken cancellationToken);
    Task SaveAccessTokenAsync(string accessToken, CancellationToken cancellationToken);
    Task ClearAsync(CancellationToken cancellationToken);
}
