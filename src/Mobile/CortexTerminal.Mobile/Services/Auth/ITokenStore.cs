namespace CortexTerminal.Mobile.Services.Auth;

public interface ITokenStore
{
    Task SaveRefreshTokenAsync(string refreshToken, CancellationToken cancellationToken);
    Task<string?> GetRefreshTokenAsync(CancellationToken cancellationToken);
    Task ClearAsync(CancellationToken cancellationToken);
}
