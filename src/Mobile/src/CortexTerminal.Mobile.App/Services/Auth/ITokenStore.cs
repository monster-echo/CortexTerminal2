namespace CortexTerminal.Mobile.App.Services.Auth;

public interface ITokenStore
{
    Task SaveTokenAsync(string token, CancellationToken cancellationToken);
    Task<string?> GetTokenAsync(CancellationToken cancellationToken);
    Task ClearAsync(CancellationToken cancellationToken);
}
