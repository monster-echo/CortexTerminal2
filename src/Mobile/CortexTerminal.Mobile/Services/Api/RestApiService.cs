using System.Text.Json;
using CortexTerminal.Mobile.Services.Auth;

namespace CortexTerminal.Mobile.Services.Api;

public sealed class RestApiService
{
    private readonly HttpClient _httpClient;
    private readonly ITokenStore _tokenStore;
    private string? _accessToken;
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    public RestApiService(HttpClient httpClient, ITokenStore tokenStore)
    {
        _httpClient = httpClient;
        _tokenStore = tokenStore;
    }

    public async Task SetAccessTokenAsync(string token, CancellationToken ct)
    {
        _accessToken = token;
    }

    public string? GetAccessToken() => _accessToken;

    public async Task<JsonElement> SendAsync(string method, string path, JsonElement? body, CancellationToken ct)
    {
        await EnsureTokenAsync(ct);

        using var request = new HttpRequestMessage(new HttpMethod(method), path);
        if (body.HasValue)
        {
            request.Content = new StringContent(body.Value.GetRawText(), System.Text.Encoding.UTF8, "application/json");
        }
        if (_accessToken is not null)
        {
            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", _accessToken);
        }

        using var response = await _httpClient.SendAsync(request, ct);

        if (response.StatusCode == System.Net.HttpStatusCode.Unauthorized && _accessToken is not null)
        {
            // Try refresh
            var refreshed = await TryRefreshTokenAsync(ct);
            if (refreshed)
            {
                using var retryRequest = new HttpRequestMessage(new HttpMethod(method), path);
                if (body.HasValue)
                {
                    retryRequest.Content = new StringContent(body.Value.GetRawText(), System.Text.Encoding.UTF8, "application/json");
                }
                retryRequest.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", _accessToken);
                using var retryResponse = await _httpClient.SendAsync(retryRequest, ct);
                return await HandleResponseAsync(retryResponse, ct);
            }
        }

        return await HandleResponseAsync(response, ct);
    }

    private async Task<JsonElement> HandleResponseAsync(HttpResponseMessage response, CancellationToken ct)
    {
        var content = await response.Content.ReadAsStringAsync(ct);

        if (!response.IsSuccessStatusCode)
        {
            throw new RestApiException((int)response.StatusCode, content);
        }

        if (string.IsNullOrWhiteSpace(content))
        {
            return JsonSerializer.Deserialize<JsonElement>("{}", _jsonOptions);
        }

        return JsonSerializer.Deserialize<JsonElement>(content, _jsonOptions);
    }

    private async Task EnsureTokenAsync(CancellationToken ct)
    {
        if (_accessToken is not null) return;
        // Token will be set by AuthService after login
    }

    private async Task<bool> TryRefreshTokenAsync(CancellationToken ct)
    {
        try
        {
            var refreshToken = await _tokenStore.GetRefreshTokenAsync(ct);
            if (refreshToken is null || _accessToken is null) return false;

            using var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/refresh");
            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", _accessToken);

            using var response = await _httpClient.SendAsync(request, ct);
            if (!response.IsSuccessStatusCode) return false;

            var json = await response.Content.ReadAsStringAsync(ct);
            var data = JsonSerializer.Deserialize<JsonElement>(json, _jsonOptions);
            _accessToken = data.GetProperty("accessToken").GetString();
            return _accessToken is not null;
        }
        catch
        {
            return false;
        }
    }
}

public sealed class RestApiException : Exception
{
    public int StatusCode { get; }
    public RestApiException(int statusCode, string message) : base(message)
    {
        StatusCode = statusCode;
    }
}
