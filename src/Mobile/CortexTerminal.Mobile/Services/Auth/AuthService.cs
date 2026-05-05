using System.Text.Json;
using CortexTerminal.Mobile.Bridge;
using CortexTerminal.Mobile.Services.Api;

namespace CortexTerminal.Mobile.Services.Auth;

public sealed class AuthService
{
    private readonly RestApiService _restApi;
    private readonly ITokenStore _tokenStore;
    private readonly WebBridge _bridge;
    private string? _accessToken;
    private string? _username;

    public string? GetCurrentToken() => _accessToken;

    public AuthService(RestApiService restApi, ITokenStore tokenStore, WebBridge bridge)
    {
        _restApi = restApi;
        _tokenStore = tokenStore;
        _bridge = bridge;
    }

    public void SetOAuthToken(string token, string username)
    {
        _accessToken = token;
        _username = username;
        _ = _restApi.SetAccessTokenAsync(token, default);
        _ = _tokenStore.SaveRefreshTokenAsync(token, default);
    }

    public async Task<BridgeResponse> HandleAsync(BridgeMessage message, CancellationToken ct)
    {
        return message.Method switch
        {
            "dev.login" => await HandleDevLoginAsync(message, ct),
            "getSession" => HandleGetSession(),
            "logout" => await HandleLogoutAsync(ct),
            "phone.sendCode" => await HandlePhoneSendCodeAsync(message, ct),
            "phone.verifyCode" => await HandlePhoneVerifyCodeAsync(message, ct),
            _ => new BridgeResponse { Ok = false, Error = $"Unknown auth method: {message.Method}" },
        };
    }

    private async Task<BridgeResponse> HandleDevLoginAsync(BridgeMessage message, CancellationToken ct)
    {
        try
        {
            var username = message.Payload?.GetProperty("username").GetString() ?? "";
            var result = await _restApi.SendAsync("POST", "/api/dev/login",
                JsonSerializer.Deserialize<JsonElement>(JsonSerializer.Serialize(new { username })),
                ct);

            _accessToken = result.GetProperty("accessToken").GetString();
            _username = username;
            _restApi.SetAccessTokenAsync(_accessToken!, ct).GetAwaiter().GetResult();

            return new BridgeResponse
            {
                Ok = true,
                Payload = JsonSerializer.Deserialize<JsonElement>(
                    JsonSerializer.Serialize(new { accessToken = _accessToken, username = _username })),
            };
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Auth] Dev login error: {ex.Message}");
            return new BridgeResponse { Ok = false, Error = ex.Message };
        }
    }

    private BridgeResponse HandleGetSession()
    {
        if (_accessToken is null || _username is null)
        {
            return new BridgeResponse { Ok = true, Payload = JsonSerializer.Deserialize<JsonElement>("null") };
        }

        return new BridgeResponse
        {
            Ok = true,
            Payload = JsonSerializer.Deserialize<JsonElement>(
                JsonSerializer.Serialize(new { token = _accessToken, username = _username })),
        };
    }

    private async Task<BridgeResponse> HandleLogoutAsync(CancellationToken ct)
    {
        _accessToken = null;
        _username = null;
        await _tokenStore.ClearAsync(ct);
        return new BridgeResponse { Ok = true };
    }

    private async Task<BridgeResponse> HandlePhoneSendCodeAsync(BridgeMessage message, CancellationToken ct)
    {
        try
        {
            var phone = message.Payload?.GetProperty("phone").GetString() ?? "";
            await _restApi.SendAsync("POST", "/api/auth/phone/send-code",
                JsonSerializer.Deserialize<JsonElement>(JsonSerializer.Serialize(new { phone })),
                ct);
            return new BridgeResponse { Ok = true };
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Auth] Phone send code error: {ex.Message}");
            return new BridgeResponse { Ok = false, Error = ex.Message };
        }
    }

    private async Task<BridgeResponse> HandlePhoneVerifyCodeAsync(BridgeMessage message, CancellationToken ct)
    {
        try
        {
            var phone = message.Payload?.GetProperty("phone").GetString() ?? "";
            var code = message.Payload?.GetProperty("code").GetString() ?? "";
            var result = await _restApi.SendAsync("POST", "/api/auth/phone/verify",
                JsonSerializer.Deserialize<JsonElement>(JsonSerializer.Serialize(new { phone, code })),
                ct);

            var accessToken = result.GetProperty("accessToken").GetString();
            var username = result.GetProperty("username").GetString();
            SetOAuthToken(accessToken!, username!);

            return new BridgeResponse
            {
                Ok = true,
                Payload = JsonSerializer.Deserialize<JsonElement>(
                    JsonSerializer.Serialize(new { username })),
            };
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Auth] Phone verify error: {ex.Message}");
            return new BridgeResponse { Ok = false, Error = ex.Message };
        }
    }
}
