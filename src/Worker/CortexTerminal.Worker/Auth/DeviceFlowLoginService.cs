using System.Net.Http.Json;
using System.Text.Json;
using CortexTerminal.Contracts.Auth;

namespace CortexTerminal.Worker.Auth;

public sealed class DeviceFlowLoginService
{
    private readonly HttpClient _httpClient;
    private readonly IWorkerTokenStore _tokenStore;

    public DeviceFlowLoginService(HttpClient httpClient, IWorkerTokenStore tokenStore)
    {
        _httpClient = httpClient;
        _tokenStore = tokenStore;
    }

    public async Task LoginAsync(CancellationToken cancellationToken)
    {
        // 1. Start device flow
        using var startResponse = await _httpClient.PostAsync("/api/auth/device-flow", content: null, cancellationToken);
        startResponse.EnsureSuccessStatusCode();
        var start = await startResponse.Content.ReadFromJsonAsync(WorkerJsonContext.Default.DeviceFlowStartResponse, cancellationToken)
            ?? throw new InvalidOperationException("Empty response from device-flow endpoint.");

        // 2. Display instructions
        Console.WriteLine();
        Console.WriteLine("  To authenticate this worker, visit:");
        Console.WriteLine($"    {start.VerificationUri}");
        Console.WriteLine();
        Console.WriteLine($"  Enter code: {start.UserCode}");
        Console.WriteLine();
        Console.WriteLine("  Waiting for authorization...");

        // 3. Poll until confirmed or expired
        var deadline = DateTime.UtcNow.AddSeconds(start.ExpiresInSeconds);
        var pollInterval = TimeSpan.FromSeconds(start.PollIntervalSeconds);

        while (DateTime.UtcNow < deadline)
        {
            await Task.Delay(pollInterval, cancellationToken);

            using var pollResponse = await _httpClient.PostAsJsonAsync(
                "/api/auth/device-flow/token",
                new DeviceFlowPollRequest(start.DeviceCode),
                WorkerJsonContext.Default.DeviceFlowPollRequest,
                cancellationToken);

            if (pollResponse.StatusCode == System.Net.HttpStatusCode.BadRequest)
            {
                var errorDoc = await pollResponse.Content.ReadFromJsonAsync(WorkerJsonContext.Default.JsonElement, cancellationToken);
                var errorCode = errorDoc.GetProperty("error").GetString();

                if (errorCode == "authorization_pending")
                    continue;

                if (errorCode == "expired_token")
                {
                    Console.WriteLine("  Device code expired. Please try again.");
                    return;
                }

                Console.WriteLine($"  Error: {errorCode}");
                return;
            }

            pollResponse.EnsureSuccessStatusCode();
            var token = await pollResponse.Content.ReadFromJsonAsync(WorkerJsonContext.Default.DeviceFlowTokenResponse, cancellationToken);

            if (token is not null)
            {
                await _tokenStore.SaveAccessTokenAsync(token.AccessToken, cancellationToken);
                Console.WriteLine("  Worker authenticated successfully!");
                Console.WriteLine("  Token saved. This worker is now bound to your account.");
                return;
            }
        }

        Console.WriteLine("  Timed out waiting for authorization.");
    }

    public async Task<string?> RefreshTokenAsync(string currentToken, CancellationToken cancellationToken)
    {
        HttpResponseMessage response;
        try
        {
            response = await _httpClient.PostAsJsonAsync(
                "/api/auth/refresh",
                new { accessToken = currentToken },
                cancellationToken);
        }
        catch (HttpRequestException)
        {
            return null;
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
                return null;

            var result = await response.Content.ReadFromJsonAsync<RefreshTokenResponse>(cancellationToken: cancellationToken);
            if (result?.AccessToken is null)
                return null;

            await _tokenStore.SaveAccessTokenAsync(result.AccessToken, cancellationToken);
            return result.AccessToken;
        }
    }

    private sealed record RefreshTokenResponse(string AccessToken);
}
