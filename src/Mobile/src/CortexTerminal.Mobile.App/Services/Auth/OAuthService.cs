using System.Text.Json;
using System.Web;

namespace CortexTerminal.Mobile.App.Services.Auth;

public sealed class OAuthService
{
    private readonly Uri _authServerBaseUri;
    private readonly AuthService _authService;
    private Func<object, string, Task>? _pushEventAsync;

    private const string CustomScheme = "cortexterminal.mobile";
    private const string CallbackPath = "/auth/callback";

    public OAuthService(Uri authServerBaseUri, AuthService authService)
    {
        _authServerBaseUri = authServerBaseUri;
        _authService = authService;
    }

    public void SetEventPusher(Func<object, string, Task> pushEventAsync)
    {
        _pushEventAsync = pushEventAsync;
    }

    public async Task StartOAuthAsync(string provider, CancellationToken ct)
    {
        var callbackUrl = $"{CustomScheme}://{CallbackPath}";
        var authUrl = new Uri(_authServerBaseUri, $"/api/auth/{provider}?redirect={Uri.EscapeDataString(callbackUrl)}");

        var result = await WebAuthenticator.Default.AuthenticateAsync(authUrl, new Uri(callbackUrl));

        var token = result?.Properties?.TryGetValue("token", out var t) == true ? t : null;
        var error = result?.Properties?.TryGetValue("error", out var e) == true ? e : null;

        if (!string.IsNullOrEmpty(error))
        {
            await SendOAuthErrorAsync(error);
            return;
        }

        if (string.IsNullOrEmpty(token))
        {
            await SendOAuthErrorAsync("No token received.");
            return;
        }

        var username = AuthService.ExtractUsernameFromJwt(token);
        _authService.SetOAuthToken(token, username);

        if (_pushEventAsync is not null)
        {
            await _pushEventAsync(new { type = "auth.oauth.success", username }, "oauth-success");
        }
    }

    public async Task HandleDeepLinkAsync(Uri uri, CancellationToken ct)
    {
        if (!string.Equals(uri.Scheme, CustomScheme, StringComparison.OrdinalIgnoreCase))
            return;

        var token = HttpUtility.ParseQueryString(uri.Query).Get("token");
        var error = HttpUtility.ParseQueryString(uri.Query).Get("error");

        if (!string.IsNullOrEmpty(error))
        {
            await SendOAuthErrorAsync(error);
            return;
        }

        if (string.IsNullOrEmpty(token))
        {
            await SendOAuthErrorAsync("No token received.");
            return;
        }

        var username = AuthService.ExtractUsernameFromJwt(token);
        _authService.SetOAuthToken(token, username);

        if (_pushEventAsync is not null)
        {
            await _pushEventAsync(new { type = "auth.oauth.success", username }, "deep-link-oauth-success");
        }
    }

    private async Task SendOAuthErrorAsync(string error)
    {
        if (_pushEventAsync is not null)
        {
            await _pushEventAsync(new { type = "auth.oauth.error", error }, "oauth-error");
        }
    }
}
