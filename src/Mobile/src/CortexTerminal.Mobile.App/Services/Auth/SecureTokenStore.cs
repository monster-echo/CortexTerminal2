namespace CortexTerminal.Mobile.App.Services.Auth;

public sealed class SecureTokenStore : ITokenStore
{
    private const string TokenKey = "auth.access_token";

    public Task SaveTokenAsync(string token, CancellationToken cancellationToken)
        => SecureStorage.Default.SetAsync(TokenKey, token);

    public Task<string?> GetTokenAsync(CancellationToken cancellationToken)
        => SecureStorage.Default.GetAsync(TokenKey);

    public Task ClearAsync(CancellationToken cancellationToken)
    {
        SecureStorage.Default.Remove(TokenKey);
        return Task.CompletedTask;
    }
}
