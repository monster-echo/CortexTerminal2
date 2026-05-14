using System.Net.Http.Json;
using System.Text;
using System.Text.Json;

namespace CortexTerminal.Mobile.App.Services.Auth;

public sealed class AuthService
{
    private readonly ITokenStore _tokenStore;
    private readonly HttpClient _httpClient;
    private string? _accessToken;
    private string? _username;

    public string? AccessToken => _accessToken;
    public string? Username => _username;

    public AuthService(ITokenStore tokenStore, HttpClient httpClient)
    {
        _tokenStore = tokenStore;
        _httpClient = httpClient;
    }

    public async Task InitializeAsync(CancellationToken ct)
    {
        AuthDiag.LogDiag($"[AUTH] InitializeAsync calling GetTokenAsync...");
        var token = await _tokenStore.GetTokenAsync(ct);
        AuthDiag.LogDiag($"[AUTH] InitializeAsync GetTokenAsync done, token={token?.Length ?? 0} chars");
        if (!string.IsNullOrEmpty(token))
        {
            _accessToken = token;
            _username = ExtractUsernameFromJwt(token);
        }
    }

    public async Task<AuthResult> SendPhoneCodeAsync(string phone, string altchaPayload, CancellationToken ct)
    {
        var response = await _httpClient.PostAsJsonAsync("/api/auth/phone/send-code", new { phone, altcha = altchaPayload }, ct);
        var body = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode)
            return new AuthResult(false, ExtractError(body));
        return new AuthResult(true, null);
    }

    public async Task<AuthResult> VerifyPhoneCodeAsync(string phone, string code, CancellationToken ct)
    {
        var response = await _httpClient.PostAsJsonAsync("/api/auth/phone/verify", new { phone, code }, ct);
        var body = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode)
            return new AuthResult(false, ExtractError(body));

        var result = JsonSerializer.Deserialize<JsonElement>(body);
        var token = result.TryGetProperty("accessToken", out var t) ? t.GetString() : null;
        var username = result.TryGetProperty("username", out var u) ? u.GetString() : null;
        if (string.IsNullOrEmpty(token))
            return new AuthResult(false, "No token received");

        await SetTokenAsync(token, username ?? "user", ct);
        return new AuthResult(true, null);
    }

    public async Task<AuthResult> LoginWithPasswordAsync(string username, string password, CancellationToken ct)
    {
        var response = await _httpClient.PostAsJsonAsync("/api/auth/password/login", new { username, password }, ct);
        var body = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode)
            return new AuthResult(false, ExtractError(body));

        var result = JsonSerializer.Deserialize<JsonElement>(body);
        var token = result.TryGetProperty("accessToken", out var t) ? t.GetString() : null;
        var user = result.TryGetProperty("username", out var u) ? u.GetString() : username;
        if (string.IsNullOrEmpty(token))
            return new AuthResult(false, "No token received");

        await SetTokenAsync(token, user ?? "user", ct);
        return new AuthResult(true, null);
    }

    public async Task<AuthResult> VerifyActivationCodeAsync(string userCode, CancellationToken ct)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/device-flow/verify")
        {
            Content = JsonContent.Create(new { userCode })
        };
        if (!string.IsNullOrEmpty(_accessToken))
            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", _accessToken);

        var response = await _httpClient.SendAsync(request, ct);
        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(ct);
            return new AuthResult(false, response.StatusCode == System.Net.HttpStatusCode.Unauthorized
                ? "token_expired" : ExtractError(body));
        }
        return new AuthResult(true, null);
    }

    public void SetOAuthToken(string token, string username)
    {
        _accessToken = token;
        _username = username;
        _ = _tokenStore.SaveTokenAsync(token, default);
    }

    public async Task<AuthResult> LoginAsGuestAsync(CancellationToken ct)
    {
        _accessToken = "guest";
        _username = "guest";
        await _tokenStore.SaveTokenAsync("guest", ct);
        return new AuthResult(true, null);
    }

    public async Task<AuthSession?> GetSessionAsync(CancellationToken ct)
    {
        AuthDiag.LogDiag($"[AUTH] GetSession START thread={Environment.CurrentManagedThreadId} hasToken={!string.IsNullOrEmpty(_accessToken)}");
        if (string.IsNullOrEmpty(_accessToken))
        {
            AuthDiag.LogDiag($"[AUTH] GetSession calling InitializeAsync...");
            await InitializeAsync(ct);
            AuthDiag.LogDiag($"[AUTH] GetSession InitializeAsync done, token={_accessToken?.Length ?? 0} chars");
        }
        if (string.IsNullOrEmpty(_accessToken))
            return null;

        return new AuthSession(_accessToken, _username ?? "user");
    }

    public async Task LogoutAsync(CancellationToken ct)
    {
        _accessToken = null;
        _username = null;
        await _tokenStore.ClearAsync(ct);
    }

    private async Task SetTokenAsync(string token, string username, CancellationToken ct)
    {
        _accessToken = token;
        _username = username;
        await _tokenStore.SaveTokenAsync(token, ct);
    }

    private static string? ExtractError(string body)
    {
        try
        {
            var json = JsonSerializer.Deserialize<JsonElement>(body);
            return json.TryGetProperty("error", out var e) ? e.GetString() : body;
        }
        catch
        {
            return body;
        }
    }

    internal static string ExtractUsernameFromJwt(string jwt)
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
            var json = Encoding.UTF8.GetString(Convert.FromBase64String(payload));
            using var doc = JsonDocument.Parse(json);
            return doc.RootElement.TryGetProperty("sub", out var sub) ? sub.GetString() ?? "user" : "user";
        }
        catch
        {
            return "user";
        }
    }
}

public sealed record AuthResult(bool Success, string? Error);
public sealed record AuthSession(string Token, string Username);

internal static class AuthDiag
{
    internal static void LogDiag(string message)
    {
#if ANDROID
        Android.Util.Log.Info("CT", message);
#else
        System.Diagnostics.Debug.WriteLine(message);
#endif
    }
}
