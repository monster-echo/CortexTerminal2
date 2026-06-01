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

    public async Task<string> GetAltchaChallengeAsync(CancellationToken ct)
    {
        var response = await _httpClient.GetAsync("/api/auth/altcha/challenge", ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadAsStringAsync(ct);
    }

    public async Task<AuthResult> SendPhoneCodeAsync(string phone, string altchaPayload, CancellationToken ct)
    {
        var response = await _httpClient.PostAsJsonAsync("/api/auth/phone/send-code", new { phone, altcha = altchaPayload }, ct);
        var body = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode)
        {
            var error = ExtractError(body);
            try
            {
                var json = JsonSerializer.Deserialize<JsonElement>(body);
                if (json.TryGetProperty("retryAfter", out var ra))
                    error = $"RATE_LIMITED:{ra.GetInt32()}";
            }
            catch { }
            return new AuthResult(false, error);
        }
        return new AuthResult(true, null);
    }

    public async Task<AuthResult> VerifyPhoneCodeAsync(string phone, string code, CancellationToken ct)
    {
        var response = await _httpClient.PostAsJsonAsync("/api/auth/phone/verify", new { phone, code }, ct);
        var body = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode)
            return new AuthResult(false, FormatError(response, ExtractError(body)));

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
            return new AuthResult(false, FormatError(response, ExtractError(body)));

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

    public async Task<AuthResult> DeleteAccountAsync(CancellationToken ct)
    {
        if (string.IsNullOrEmpty(_accessToken))
            return new AuthResult(false, "Not authenticated");

        var request = new HttpRequestMessage(HttpMethod.Delete, "/api/me/account");
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", _accessToken);

        var response = await _httpClient.SendAsync(request, ct);
        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(ct);
            return new AuthResult(false, FormatError(response, ExtractError(body)));
        }

        await LogoutAsync(ct);
        return new AuthResult(true, null);
    }

    public async Task<AuthResult> SetPasswordAsync(string? currentPassword, string newPassword, CancellationToken ct)
    {
        if (string.IsNullOrEmpty(_accessToken))
            return new AuthResult(false, "Not authenticated");

        var request = new HttpRequestMessage(HttpMethod.Put, "/api/me/password")
        {
            Content = JsonContent.Create(new { currentPassword, newPassword })
        };
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", _accessToken);

        var response = await _httpClient.SendAsync(request, ct);
        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(ct);
            return new AuthResult(false, FormatError(response, ExtractError(body)));
        }

        return new AuthResult(true, null);
    }

    public async Task<UserProfile?> GetProfileAsync(CancellationToken ct)
    {
        if (string.IsNullOrEmpty(_accessToken))
            return null;

        var request = new HttpRequestMessage(HttpMethod.Get, "/api/me/profile");
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", _accessToken);

        var response = await _httpClient.SendAsync(request, ct);
        if (!response.IsSuccessStatusCode)
            return null;

        var body = await response.Content.ReadAsStringAsync(ct);
        var json = JsonSerializer.Deserialize<JsonElement>(body);
        var username = json.TryGetProperty("username", out var u) ? u.GetString() : null;
        var hasPassword = json.TryGetProperty("hasPassword", out var hp) && hp.GetBoolean();
        var avatarUrl = json.TryGetProperty("avatarUrl", out var av) ? av.GetString() : null;

        return new UserProfile(username ?? "user", hasPassword, avatarUrl);
    }

    public async Task<AvatarUpdateResult> UpdateAvatarAsync(string base64Image, CancellationToken ct)
    {
        if (string.IsNullOrEmpty(_accessToken))
            return new AvatarUpdateResult(false, null, "Not authenticated");

        var request = new HttpRequestMessage(HttpMethod.Put, "/api/me/avatar")
        {
            Content = new StringContent(base64Image, Encoding.UTF8, "text/plain")
        };
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", _accessToken);

        var response = await _httpClient.SendAsync(request, ct);
        var body = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode)
            return new AvatarUpdateResult(false, null, ExtractError(body));

        var json = JsonSerializer.Deserialize<JsonElement>(body);
        var avatarUrl = json.TryGetProperty("avatarUrl", out var av) ? av.GetString() : null;
        return new AvatarUpdateResult(true, avatarUrl, null);
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

    private static string FormatError(HttpResponseMessage response, string? extractedError)
    {
        var statusCode = (int)response.StatusCode;
        if (statusCode >= 500)
            return "Internal server error";
        return !string.IsNullOrEmpty(extractedError) ? extractedError : "Request failed";
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
public sealed record UserProfile(string Username, bool HasPassword, string? AvatarUrl);
public sealed record AvatarUpdateResult(bool Success, string? AvatarUrl, string? Error);

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
