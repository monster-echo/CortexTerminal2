using System.Net.Http.Json;
using CortexTerminal.Contracts.Auth;

namespace CortexTerminal.Mobile.Services.Auth;

public sealed class DeviceFlowService(HttpClient httpClient, ITokenStore tokenStore)
{
    public async Task<DeviceFlowStartResponse?> StartAsync(CancellationToken cancellationToken)
    {
        using var response = await httpClient.PostAsync("/api/auth/device-flow", content: null, cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<DeviceFlowStartResponse>(cancellationToken: cancellationToken);
    }

    public async Task<DeviceFlowTokenResponse?> PollAsync(string deviceCode, CancellationToken cancellationToken)
    {
        using var response = await httpClient.PostAsJsonAsync("/connect/token", new Dictionary<string, string?>
        {
            ["grant_type"] = "urn:ietf:params:oauth:grant-type:device_code",
            ["device_code"] = deviceCode
        }, cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            return null;
        }

        var token = await response.Content.ReadFromJsonAsync<DeviceFlowTokenResponse>(cancellationToken: cancellationToken);
        if (token is not null)
        {
            await tokenStore.SaveRefreshTokenAsync(token.RefreshToken, cancellationToken);
        }

        return token;
    }
}
