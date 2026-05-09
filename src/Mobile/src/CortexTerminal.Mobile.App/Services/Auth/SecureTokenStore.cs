namespace CortexTerminal.Mobile.App.Services.Auth;

public sealed class SecureTokenStore : ITokenStore
{
    private const string TokenKey = "auth.access_token";

    public Task SaveTokenAsync(string token, CancellationToken cancellationToken)
    {
        AuthDiag.LogDiag($"[TOKEN] SaveTokenAsync START thread={Environment.CurrentManagedThreadId}");
        return SecureStorage.Default.SetAsync(TokenKey, token);
    }

    public Task<string?> GetTokenAsync(CancellationToken cancellationToken)
    {
        AuthDiag.LogDiag($"[TOKEN] GetTokenAsync START thread={Environment.CurrentManagedThreadId}");
        var task = SecureStorage.Default.GetAsync(TokenKey);
        AuthDiag.LogDiag($"[TOKEN] GetTokenAsync task created, status={task.Status}");
        return task;
    }

    public Task ClearAsync(CancellationToken cancellationToken)
    {
        SecureStorage.Default.Remove(TokenKey);
        return Task.CompletedTask;
    }
}
