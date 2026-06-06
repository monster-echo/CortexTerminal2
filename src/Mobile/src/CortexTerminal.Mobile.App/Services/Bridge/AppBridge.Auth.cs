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
    public Task<string> GetAvailableAuthMethodsAsync()
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_authService is null) throw new InvalidOperationException("AuthService not configured");
            var methods = await _authService.GetAvailableAuthMethodsAsync(default);
            return new { methods };
        });
    }

    [BridgeMethod]
    public Task<string> GetCaptchaChallengeAsync()
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_authService is null) throw new InvalidOperationException("AuthService not configured");
            var challenge = await _authService.GetCaptchaChallengeAsync(default);
            return new { challenge.Id, challenge.BackgroundImage, challenge.SliderImage, challenge.Y };
        });
    }

    [BridgeMethod]
    public Task<string> VerifyCaptchaAsync(string id, int x)
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_authService is null) throw new InvalidOperationException("AuthService not configured");
            var result = await _authService.VerifyCaptchaAsync(id, x, default);
            if (!result.Success) throw new InvalidOperationException("Captcha verification failed");
            return new { captchaToken = result.CaptchaToken };
        });
    }

    [BridgeMethod]
    public Task<string> SendPhoneCodeAsync(string phone, string? captchaToken)
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_authService is null) throw new InvalidOperationException("AuthService not configured");
            var result = await _authService.SendPhoneCodeAsync(phone, captchaToken, default);
            if (result.CaptchaRequired) return new { success = false, captchaRequired = true };
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
    public Task<string> LoginWithPasswordAsync(string username, string password, string? captchaToken)
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_authService is null) throw new InvalidOperationException("AuthService not configured");
            var result = await _authService.LoginWithPasswordAsync(username, password, captchaToken, default);
            if (result.CaptchaRequired) return new { success = false, captchaRequired = true };
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

    [BridgeMethod]
    public Task<string> VerifyActivationCodeAsync(string userCode)
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_authService is null) throw new InvalidOperationException("AuthService not configured");
            var result = await _authService.VerifyActivationCodeAsync(userCode, default);
            if (!result.Success) throw new InvalidOperationException(result.Error);
            return new { confirmed = true };
        });
    }

    [BridgeMethod]
    public Task<string> DeleteAccountAsync()
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_authService is null) throw new InvalidOperationException("AuthService not configured");
            var result = await _authService.DeleteAccountAsync(default);
            if (!result.Success) throw new InvalidOperationException(result.Error);
            return new { success = true };
        });
    }

    [BridgeMethod]
    public Task<string> SetPasswordAsync(string? currentPassword, string newPassword)
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_authService is null) throw new InvalidOperationException("AuthService not configured");
            var result = await _authService.SetPasswordAsync(currentPassword, newPassword, default);
            if (!result.Success) throw new InvalidOperationException(result.Error);
            return new { success = true };
        });
    }

    [BridgeMethod]
    public Task<string> GetProfileAsync()
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_authService is null) return (object?)null;
            var profile = await _authService.GetProfileAsync(default);
            if (profile is null) return (object?)null;
            return new { profile.Username, profile.HasPassword, profile.AvatarUrl };
        });
    }

    [BridgeMethod]
    public Task<string> UpdateAvatarAsync(string base64Image)
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_authService is null) throw new InvalidOperationException("AuthService not configured");
            var result = await _authService.UpdateAvatarAsync(base64Image, default);
            if (!result.Success) throw new InvalidOperationException(result.Error);
            return new { success = true, avatarUrl = result.AvatarUrl };
        });
    }
}
