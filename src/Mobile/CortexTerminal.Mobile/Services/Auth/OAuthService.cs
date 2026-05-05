using System.Text.Json;
using System.Web;
using CortexTerminal.Mobile.Bridge;

namespace CortexTerminal.Mobile.Services.Auth;

public sealed class OAuthService
{
    private readonly Uri _gatewayBaseUri;
    private readonly AuthService _authService;
    private readonly WebBridge _bridge;

    private const string CustomScheme = "cortexterminal";
    private const string CallbackPath = "/auth/callback";

    public OAuthService(Uri gatewayBaseUri, AuthService authService, WebBridge bridge)
    {
        _gatewayBaseUri = gatewayBaseUri;
        _authService = authService;
        _bridge = bridge;
    }

    public async Task<BridgeResponse> HandleAsync(BridgeMessage message, CancellationToken ct)
    {
        return message.Method switch
        {
            "oauth.start" => await HandleStartAsync(message, ct),
            _ => new BridgeResponse { Ok = false, Error = $"Unknown auth method: {message.Method}" },
        };
    }

    private async Task<BridgeResponse> HandleStartAsync(BridgeMessage message, CancellationToken ct)
    {
        var provider = message.Payload?.GetProperty("provider").GetString() ?? "";
        if (provider is not ("github" or "google" or "apple"))
        {
            return new BridgeResponse { Ok = false, Error = "Unsupported OAuth provider." };
        }

        var redirectUrl = $"{CustomScheme}://{CallbackPath}";
        var oauthStartUrl = $"{_gatewayBaseUri}api/auth/{provider}?redirect={Uri.EscapeDataString(redirectUrl)}";

        try
        {
            await Browser.OpenAsync(oauthStartUrl, BrowserLaunchMode.SystemPreferred);
        }
        catch (Exception ex)
        {
            return new BridgeResponse { Ok = false, Error = $"Could not open browser: {ex.Message}" };
        }

        return new BridgeResponse { Ok = true };
    }

    /// <summary>
    /// Called by the platform layer when a deep link is received (e.g. cortexterminal://auth/callback?token=xxx).
    /// Extracts the JWT, applies it via AuthService, and pushes an event to the WebView.
    /// </summary>
    public async Task HandleDeepLinkAsync(Uri uri, CancellationToken ct)
    {
        Console.WriteLine($"[OAuth] HandleDeepLink: {uri}");

        if (!string.Equals(uri.Scheme, CustomScheme, StringComparison.OrdinalIgnoreCase))
            return;

        var token = HttpUtility.ParseQueryString(uri.Query).Get("token");
        var error = HttpUtility.ParseQueryString(uri.Query).Get("error");

        Console.WriteLine($"[OAuth] token={token?[..Math.Min(20, token.Length)]}..., error={error}");

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

        var username = ExtractUsernameFromJwt(token);
        _authService.SetOAuthToken(token, username);

        await _bridge.SendEventAsync(new BridgeEvent
        {
            Channel = "auth",
            Method = "oauth.success",
            Payload = JsonSerializer.Deserialize<JsonElement>(
                JsonSerializer.Serialize(new { username })),
        });
    }

    private async Task SendOAuthErrorAsync(string error)
    {
        await _bridge.SendEventAsync(new BridgeEvent
        {
            Channel = "auth",
            Method = "oauth.error",
            Payload = JsonSerializer.Deserialize<JsonElement>(
                JsonSerializer.Serialize(new { error })),
        });
    }

    private static string ExtractUsernameFromJwt(string jwt)
    {
        try
        {
            var segments = jwt.Split('.');
            if (segments.Length < 2) return "user";

            var payload = segments[1];
            payload = payload.Replace('-', '+').Replace('_', '/');
            switch (payload.Length % 4)
            {
                case 2: payload += "=="; break;
                case 3: payload += "="; break;
            }

            var json = System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(payload));
            using var doc = JsonDocument.Parse(json);
            return doc.RootElement.TryGetProperty("sub", out var sub) ? sub.GetString() ?? "user" : "user";
        }
        catch
        {
            return "user";
        }
    }
}
