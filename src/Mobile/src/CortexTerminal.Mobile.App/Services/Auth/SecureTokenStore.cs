namespace CortexTerminal.Mobile.App.Services.Auth;

public sealed class SecureTokenStore : ITokenStore
{
    private const string TokenKey = "auth.access_token";

    public Task SaveTokenAsync(string token, CancellationToken cancellationToken)
    {
        AuthDiag.LogDiag($"[TOKEN] SaveTokenAsync START thread={Environment.CurrentManagedThreadId}");
#if DEBUG
        Preferences.Default.Set(TokenKey, token);
        return Task.CompletedTask;
#else
        return SecureStorage.Default.SetAsync(TokenKey, token);
#endif
    }

    public Task<string?> GetTokenAsync(CancellationToken cancellationToken)
    {
        AuthDiag.LogDiag($"[TOKEN] GetTokenAsync START thread={Environment.CurrentManagedThreadId}");
#if DEBUG
        var value = Preferences.Default.Get<string?>(TokenKey, null);
        return Task.FromResult(value);
#else
        var task = SecureStorage.Default.GetAsync(TokenKey);
        AuthDiag.LogDiag($"[TOKEN] GetTokenAsync task created, status={task.Status}");
        return task;
#endif
    }

    public Task ClearAsync(CancellationToken cancellationToken)
    {
#if DEBUG
        Preferences.Default.Remove(TokenKey);
#else
        SecureStorage.Default.Remove(TokenKey);
#endif
        return Task.CompletedTask;
    }
}
