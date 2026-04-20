namespace CortexTerminal.Mobile.Services.Auth;

public sealed class SecureTokenStore : ITokenStore
{
    private const string RefreshTokenKey = "auth.refresh_token";

    public Task SaveRefreshTokenAsync(string refreshToken, CancellationToken cancellationToken)
        => SecureStorage.Default.SetAsync(RefreshTokenKey, refreshToken);

    public Task<string?> GetRefreshTokenAsync(CancellationToken cancellationToken)
        => SecureStorage.Default.GetAsync(RefreshTokenKey);

    public Task ClearAsync(CancellationToken cancellationToken)
    {
        SecureStorage.Default.Remove(RefreshTokenKey);
        return Task.CompletedTask;
    }
}
