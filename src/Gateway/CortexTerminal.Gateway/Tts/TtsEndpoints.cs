using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace CortexTerminal.Gateway.Tts;

public static class TtsEndpoints
{
    public static void Map(WebApplication app, TtsOptions options)
    {
        var hasCloudflare = !string.IsNullOrEmpty(options.Cloudflare.AccountId)
                         && !string.IsNullOrEmpty(options.Cloudflare.ApiToken);
        var hasAliyun = !string.IsNullOrEmpty(options.Aliyun.ApiKey);

        if (!hasCloudflare && !hasAliyun)
            return;

        app.MapPost("/api/tts/synthesize", async (
            TtsRequest request,
            IHttpClientFactory httpClientFactory) =>
        {
            if (string.IsNullOrWhiteSpace(request.Text))
                return Results.BadRequest(new { error = "Text is required" });

            if (request.Text.Length > 5000)
                return Results.BadRequest(new { error = "Text too long (max 5000 characters)" });

            var provider = request.Provider?.ToLowerInvariant();

            return provider switch
            {
                "cloudflare" when !hasCloudflare
                    => Results.BadRequest(new { error = "Cloudflare TTS is not configured" }),
                "cloudflare"
                    => await SynthesizeCloudflare(request.Text, options.Cloudflare, httpClientFactory),
                "aliyun" when !hasAliyun
                    => Results.BadRequest(new { error = "Aliyun TTS is not configured" }),
                "aliyun"
                    => await SynthesizeAliyun(request.Text, options.Aliyun, httpClientFactory),
                null or "" when hasCloudflare
                    => await SynthesizeCloudflare(request.Text, options.Cloudflare, httpClientFactory),
                null or "" when hasAliyun
                    => await SynthesizeAliyun(request.Text, options.Aliyun, httpClientFactory),
                _ => Results.Json(new { error = "No TTS provider available" }, statusCode: 503)
            };
        }).RequireAuthorization();
    }

    private static async Task<IResult> SynthesizeCloudflare(
        string text, CloudflareTtsOptions options, IHttpClientFactory httpFactory)
    {
        var http = httpFactory.CreateClient();
        var url = $"https://api.cloudflare.com/client/v4/accounts/{options.AccountId}/ai/run/@cf/meta/mms-tts-1";

        var request = new HttpRequestMessage(HttpMethod.Post, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", options.ApiToken);
        request.Content = new StringContent(
            JsonSerializer.Serialize(new { text }),
            Encoding.UTF8,
            "application/json");

        var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();

        var contentType = response.Content.Headers.ContentType?.MediaType ?? "audio/wav";
        var stream = await response.Content.ReadAsStreamAsync();
        return Results.Stream(stream, contentType);
    }

    private static async Task<IResult> SynthesizeAliyun(
        string text, AliyunTtsOptions options, IHttpClientFactory httpFactory)
    {
        var http = httpFactory.CreateClient();
        var url = "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation";

        var body = new
        {
            model = options.Model,
            input = new
            {
                text,
                voice = options.Voice
            },
            parameters = new
            {
                format = "mp3",
                sample_rate = 22050
            }
        };

        var request = new HttpRequestMessage(HttpMethod.Post, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", options.ApiKey);
        request.Content = new StringContent(
            JsonSerializer.Serialize(body),
            Encoding.UTF8,
            "application/json");

        var response = await http.SendAsync(request);
        response.EnsureSuccessStatusCode();

        var jsonBody = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(jsonBody);

        var audioUrl = doc.RootElement
            .GetProperty("output").GetProperty("audio").GetString();

        if (string.IsNullOrEmpty(audioUrl))
            throw new InvalidOperationException("Aliyun TTS response missing audio URL");

        var audioResponse = await http.GetAsync(audioUrl, HttpCompletionOption.ResponseHeadersRead);
        audioResponse.EnsureSuccessStatusCode();

        var audioStream = await audioResponse.Content.ReadAsStreamAsync();
        var audioContentType = audioResponse.Content.Headers.ContentType?.MediaType ?? "audio/mpeg";

        return Results.Stream(audioStream, audioContentType);
    }
}

record TtsRequest(string Text, string? Provider = null);
