using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using CortexTerminal.Contracts.Auth;

namespace CortexTerminal.Worker.Auth;

public sealed record RefreshTokenResponse(string AccessToken);

/// <summary>
/// A structured device-flow milestone for programmatic callers (e.g. <c>corterm login --json</c>).
/// <c>Stage</c> is <c>"code"</c> (device code issued, waiting for authorization),
/// <c>"success"</c> (token saved), or <c>"error"</c> (poll failed or timed out; see <c>Message</c>).
/// </summary>
public sealed record DeviceFlowStage(
    string Stage,
    string? VerificationUri = null,
    string? UserCode = null,
    int? ExpiresInSeconds = null,
    int? PollIntervalSeconds = null,
    string? Message = null);

public sealed class DeviceFlowLoginService
{
    private readonly HttpClient _httpClient;
    private readonly IWorkerTokenStore _tokenStore;

    public DeviceFlowLoginService(HttpClient httpClient, IWorkerTokenStore tokenStore)
    {
        _httpClient = httpClient;
        _tokenStore = tokenStore;
    }

    public Task LoginAsync(CancellationToken cancellationToken)
        => LoginAsync(cancellationToken, onStage: null);

    /// <summary>
    /// Runs the device flow. When <paramref name="onStage"/> is non-null, human console output is
    /// suppressed and each milestone is pushed through the callback (for <c>--json</c> callers);
    /// otherwise the original interactive console behavior is preserved.
    /// </summary>
    public async Task LoginAsync(CancellationToken cancellationToken, Action<DeviceFlowStage>? onStage)
    {
        // 1. Start device flow
        using var startResponse = await _httpClient.PostAsync("/api/auth/device-flow", content: null, cancellationToken);
        startResponse.EnsureSuccessStatusCode();
        var start = await startResponse.Content.ReadFromJsonAsync(WorkerJsonContext.Default.DeviceFlowStartResponse, cancellationToken)
            ?? throw new InvalidOperationException("Empty response from device-flow endpoint.");

        // 2. Display instructions (or emit the device-code stage to programmatic callers)
        if (onStage is not null)
        {
            onStage(new DeviceFlowStage("code", start.VerificationUri, start.UserCode, start.ExpiresInSeconds, start.PollIntervalSeconds));
        }
        else
        {
            // QR-first flow: encode verification_uri_complete so a scan by the Corterm
            // app (or any camera hitting the gateway's auto-confirm page) authorizes
            // without typing. The user code and URL stay as manual fallbacks.
            var completeUri = $"{start.VerificationUri}?code={start.UserCode}";
            Console.WriteLine();
            Console.WriteLine("  用云枢终端 App 扫描二维码完成授权");
            Console.WriteLine("  Or scan with the Corterm app to authorize this worker:");
            Console.WriteLine();
            PrintAsciiQr(completeUri);
            Console.WriteLine();
            Console.WriteLine($"  Or enter code manually: {start.UserCode}");
            Console.WriteLine($"  ({start.VerificationUri})");
            Console.WriteLine();
            Console.WriteLine("  Waiting for authorization...");
        }

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
                    if (onStage is not null)
                    {
                        onStage(new DeviceFlowStage("error", Message: "Device code expired. Please try again."));
                    }
                    else
                    {
                        Console.WriteLine("  Device code expired. Please try again.");
                    }
                    return;
                }

                if (onStage is not null)
                {
                    onStage(new DeviceFlowStage("error", Message: $"Error: {errorCode}"));
                }
                else
                {
                    Console.WriteLine($"  Error: {errorCode}");
                }
                return;
            }

            pollResponse.EnsureSuccessStatusCode();
            var token = await pollResponse.Content.ReadFromJsonAsync(WorkerJsonContext.Default.DeviceFlowTokenResponse, cancellationToken);

            if (token is not null)
            {
                await _tokenStore.SaveAccessTokenAsync(token.AccessToken, cancellationToken);
                if (onStage is not null)
                {
                    onStage(new DeviceFlowStage("success"));
                }
                else
                {
                    Console.WriteLine("  Worker authenticated successfully!");
                    Console.WriteLine("  Token saved. Run 'corterm' to start the worker.");
                }
                return;
            }
        }

        if (onStage is not null)
        {
            onStage(new DeviceFlowStage("error", Message: "Timed out waiting for authorization."));
        }
        else
        {
            Console.WriteLine("  Timed out waiting for authorization.");
        }
    }

    /// <summary>
    /// Renders the payload as a scannable ASCII QR (half-block chars, 4-module quiet
    /// zone). Uses white-on-default via two chars per module so the modules stay square
    /// in typical monospace terminal fonts.
    /// </summary>
    private static void PrintAsciiQr(string payload)
    {
        using var generator = new QRCoder.QRCodeGenerator();
        var data = generator.CreateQrCode(payload, QRCoder.QRCodeGenerator.ECCLevel.L);
        var matrix = data.ModuleMatrix;
        var quiet = 4;
        const string dark = "██";
        const string light = "  ";
        for (var row = 0; row < matrix.Count + quiet * 2; row++)
        {
            var line = string.Empty;
            for (var col = 0; col < matrix.Count + quiet * 2; col++)
            {
                var module = row >= quiet && col >= quiet &&
                             row < matrix.Count + quiet && col < matrix.Count + quiet &&
                             matrix[row - quiet][col - quiet];
                line += module ? dark : light;
            }

            Console.WriteLine("  " + line);
        }
    }

    public async Task<string?> RefreshTokenAsync(string currentToken, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/auth/refresh");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", currentToken);

        HttpResponseMessage response;
        try
        {
            response = await _httpClient.SendAsync(request, cancellationToken);
        }
        catch (HttpRequestException)
        {
            return null;
        }

        using (response)
        {
            // 401 = token rejected by gateway (expired or revoked). Not recoverable
            // by retrying — caller must exit so user can re-login.
            if (response.StatusCode == System.Net.HttpStatusCode.Unauthorized)
                throw new UnauthorizedAccessException("Token rejected by gateway.");

            if (!response.IsSuccessStatusCode)
                return null;

            var result = await response.Content.ReadFromJsonAsync(
                WorkerJsonContext.Default.RefreshTokenResponse, cancellationToken);
            if (result?.AccessToken is null)
                return null;

            await _tokenStore.SaveAccessTokenAsync(result.AccessToken, cancellationToken);
            return result.AccessToken;
        }
    }
}
