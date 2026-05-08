using CortexTerminal.Mobile.Core.Bridge;
using CortexTerminal.Mobile.App.Services.Auth;

namespace CortexTerminal.Mobile.App.Services.Bridge;

public sealed partial class AppBridge
{
    private AuthService? _authService;
    private OAuthService? _oauthService;

    internal void SetAuthServices(AuthService authService, OAuthService oauthService)
    {
        _authService = authService;
        _oauthService = oauthService;
        oauthService.SetEventPusher(SendEventToWebViewAsync);
    }

    [BridgeMethod]
    public Task<string> SendPhoneCodeAsync(string phone)
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_authService is null) throw new InvalidOperationException("AuthService not configured");
            var result = await _authService.SendPhoneCodeAsync(phone, default);
            if (!result.Success) throw new InvalidOperationException(result.Error);
            return new { success = true };
        });
    }

    [BridgeMethod]
    public Task<string> VerifyPhoneCodeAsync(string phone, string code)
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_authService is null) throw new InvalidOperationException("AuthService not configured");
            var result = await _authService.VerifyPhoneCodeAsync(phone, code, default);
            if (!result.Success) throw new InvalidOperationException(result.Error);
            var session = await _authService.GetSessionAsync(default);
            return new { success = true, username = session?.Username };
        });
    }

    [BridgeMethod]
    public Task<string> StartOAuthAsync(string provider)
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_oauthService is null) throw new InvalidOperationException("OAuthService not configured");
            await _oauthService.StartOAuthAsync(provider, default);
            return new { success = true };
        });
    }

    [BridgeMethod]
    public Task<string> GetSessionAsync()
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_authService is null) return (object?)null;
            var session = await _authService.GetSessionAsync(default);
            if (session is null) return (object?)null;
            return new { session.Token, session.Username };
        });
    }

    [BridgeMethod]
    public Task<string> LogoutAsync()
    {
        return ExecuteSafeVoidAsync(async () =>
        {
            if (_authService is null) return;
            await _authService.LogoutAsync(default);
        });
    }

    [BridgeMethod]
    public Task<string> GuestLoginAsync()
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_authService is null) throw new InvalidOperationException("AuthService not configured");
            var result = await _authService.LoginAsGuestAsync(default);
            if (!result.Success) throw new InvalidOperationException(result.Error);
            return new { success = true, username = "guest" };
        });
    }
}
