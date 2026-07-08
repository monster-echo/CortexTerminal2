using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CortexTerminal.Mobile.App.Services.Auth;

namespace CortexTerminal.Mobile.App.Services.Support;

/// <summary>
/// Fetches gateway-served support contact info, uploads feedback screenshots to S3
/// via gateway-brokered presigned URLs, and submits signed feedback to n8n.
/// </summary>
public sealed class SupportService
{
    private readonly HttpClient _httpClient;
    private readonly AuthService _authService;

    private const string FeedbackWebhookUrl = "https://n8n.0x2a.top/webhook/corterm-feedback";
    private const string FeedbackHmacSecret = "df32c11ff79353e1d04ef45a62ece648c2f4307296f3059db7ec735a6fb219c9";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = false,
    };

    public SupportService(HttpClient httpClient, AuthService authService)
    {
        _httpClient = httpClient;
        _authService = authService;
    }

    public async Task<SupportInfo?> GetSupportInfoAsync(CancellationToken ct)
    {
        var response = await _httpClient.GetAsync("/api/support/info", ct);
        if (!response.IsSuccessStatusCode) return null;
        var body = await response.Content.ReadAsStringAsync(ct);
        using var doc = JsonDocument.Parse(body);
        var root = doc.RootElement;
        return new SupportInfo(
            QqGroup: ParseGroup(root, "qqGroup"),
            TelegramGroup: ParseGroup(root, "telegramGroup"),
            Email: root.TryGetProperty("email", out var e) ? e.GetString() ?? string.Empty : string.Empty);
    }

    private static SupportGroup? ParseGroup(JsonElement root, string name)
    {
        if (!root.TryGetProperty(name, out var g) || g.ValueKind != JsonValueKind.Object) return null;
        return new SupportGroup(
            Name: g.TryGetProperty("name", out var n) ? n.GetString() ?? string.Empty : string.Empty,
            Number: g.TryGetProperty("number", out var num) ? num.GetString() ?? string.Empty : string.Empty,
            Url: g.TryGetProperty("url", out var u) ? u.GetString() ?? string.Empty : string.Empty,
            QrCodeUrl: g.TryGetProperty("qrCodeUrl", out var qr) ? qr.GetString() ?? string.Empty : string.Empty);
    }

    /// <summary>
    /// Requests a presigned PUT URL from the gateway, uploads the image bytes to S3,
    /// and returns the public gateway-proxied image URL to embed in the feedback payload.
    /// </summary>
    public async Task<string> UploadFeedbackImageAsync(string localPath, string filename, string contentType, CancellationToken ct)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/me/feedback/uploads")
        {
            Content = JsonContent.Create(new { filename }),
        };
        AddAuth(request);
        var reqResponse = await _httpClient.SendAsync(request, ct);
        var reqBody = await reqResponse.Content.ReadAsStringAsync(ct);
        if (!reqResponse.IsSuccessStatusCode)
            throw new InvalidOperationException($"Upload URL request failed ({(int)reqResponse.StatusCode})");

        using var doc = JsonDocument.Parse(reqBody);
        var uploadUrl = doc.RootElement.TryGetProperty("uploadUrl", out var u) ? u.GetString() : null;
        var imageUrl = doc.RootElement.TryGetProperty("imageUrl", out var i) ? i.GetString() : null;
        if (string.IsNullOrEmpty(uploadUrl) || string.IsNullOrEmpty(imageUrl))
            throw new InvalidOperationException("Missing uploadUrl/imageUrl in response");

        var bytes = await File.ReadAllBytesAsync(localPath, ct);
        var putContent = new ByteArrayContent(bytes);
        putContent.Headers.ContentType = new MediaTypeHeaderValue(contentType);
        var putRequest = new HttpRequestMessage(HttpMethod.Put, uploadUrl) { Content = putContent };
        var putResponse = await _httpClient.SendAsync(putRequest, ct);
        if (!putResponse.IsSuccessStatusCode)
            throw new InvalidOperationException($"Image upload failed ({(int)putResponse.StatusCode})");
        return imageUrl;
    }

    public async Task<string> SubmitFeedbackAsync(
        string type, string subtype, string content, string contact,
        string username, string lang, string appVersion, string attachmentsJson, CancellationToken ct)
    {
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        var nonce = $"fb-{timestamp}-{Random.Shared.Next(0, 1_000_000)}";

        var attachments = ParseAttachments(attachmentsJson);

        var payload = new Dictionary<string, object?>
        {
            ["type"] = type,
            ["subtype"] = subtype,
            ["content"] = content,
            ["contact"] = contact,
            ["username"] = username,
            ["lang"] = lang,
            ["appVersion"] = appVersion,
            ["timestamp"] = timestamp,
            ["nonce"] = nonce,
            ["attachments"] = attachments,
        };
        var body = JsonSerializer.Serialize(payload, JsonOptions);
        var signature = ComputeHmacSha256(FeedbackHmacSecret, body);

        var request = new HttpRequestMessage(HttpMethod.Post, FeedbackWebhookUrl)
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json"),
        };
        request.Headers.Add("X-Signature", signature);

        var response = await _httpClient.SendAsync(request, ct);
        var respBody = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode)
            throw new InvalidOperationException($"Feedback submit failed ({(int)response.StatusCode})");

        using var doc = JsonDocument.Parse(respBody);
        var ticketId = doc.RootElement.TryGetProperty("ticketId", out var t) ? t.GetString() : null;
        if (string.IsNullOrEmpty(ticketId))
            throw new InvalidOperationException("No ticketId in response");
        return ticketId!;
    }

    private static List<string> ParseAttachments(string attachmentsJson)
    {
        if (string.IsNullOrWhiteSpace(attachmentsJson)) return new List<string>();
        try
        {
            return JsonSerializer.Deserialize<List<string>>(attachmentsJson) ?? new List<string>();
        }
        catch
        {
            return new List<string>();
        }
    }

    private void AddAuth(HttpRequestMessage request)
    {
        var token = _authService.AccessToken;
        if (!string.IsNullOrEmpty(token))
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }
    }

    private static string ComputeHmacSha256(string secret, string message)
    {
        var keyBytes = Encoding.UTF8.GetBytes(secret);
        using var hmac = new HMACSHA256(keyBytes);
        var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(message));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}

public sealed record SupportInfo(SupportGroup? QqGroup, SupportGroup? TelegramGroup, string Email);

public sealed record SupportGroup(string Name, string Number, string Url, string QrCodeUrl);
