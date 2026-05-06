using System.Text.Json;
using System.Text.Json.Serialization;

namespace CortexTerminal.Mobile.Bridge;

public sealed class WebBridge
{
    private HybridWebView? _webView;
    private readonly Dictionary<(string channel, string method), Func<BridgeMessage, Task<BridgeResponse>>> _handlers = new();
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public void Attach(HybridWebView webView)
    {
        _webView = webView;
        _webView.RawMessageReceived += OnRawMessageReceived;
    }

    public void RegisterHandler(string channel, string method, Func<BridgeMessage, Task<BridgeResponse>> handler)
    {
        _handlers[(channel, method)] = handler;
    }

    public async Task SendResponseAsync(BridgeResponse response)
    {
        var json = JsonSerializer.Serialize(response, _jsonOptions);
        await SendToWebViewAsync(json);
    }

    public async Task SendEventAsync(BridgeEvent @event)
    {
        var json = JsonSerializer.Serialize(@event, _jsonOptions);
        await SendToWebViewAsync(json);
    }

    private async void OnRawMessageReceived(object? sender, HybridWebViewRawMessageReceivedEventArgs e)
    {
        string? messageId = null;
        try
        {
            var message = JsonSerializer.Deserialize<BridgeMessage>(e.Message!, _jsonOptions);
            if (message is null) return;
            messageId = message.Id;

            if (!_handlers.TryGetValue((message.Channel, message.Method), out var handler))
            {
                // Try wildcard handler for the channel
                if (!_handlers.TryGetValue((message.Channel, "*"), out handler))
                {
                    await SendResponseAsync(new BridgeResponse
                    {
                        Id = message.Id,
                        Ok = false,
                        Error = $"No handler for {message.Channel}:{message.Method}",
                    });
                    return;
                }
            }

            var response = await handler(message);
            response.Id = message.Id;
            await SendResponseAsync(response);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[WebBridge] Error processing message: {ex.Message}");
            if (messageId is not null)
            {
                try
                {
                    await SendResponseAsync(new BridgeResponse
                    {
                        Id = messageId,
                        Ok = false,
                        Error = ex.Message,
                    });
                }
                catch { /* best effort */ }
            }
        }
    }

    private Task SendToWebViewAsync(string json)
    {
        if (_webView is null) return Task.CompletedTask;
        var completion = new TaskCompletionSource<object?>();
        MainThread.BeginInvokeOnMainThread(() =>
        {
            try
            {
                _webView.SendRawMessage(json);
                completion.TrySetResult(null);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[WebBridge] SendRawMessage error: {ex.Message}");
                completion.TrySetException(ex);
            }
        });
        return completion.Task;
    }

}

public sealed class BridgeMessage
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("type")]
    public string Type { get; set; } = "";

    [JsonPropertyName("channel")]
    public string Channel { get; set; } = "";

    [JsonPropertyName("method")]
    public string Method { get; set; } = "";

    [JsonPropertyName("payload")]
    public JsonElement? Payload { get; set; }

    [JsonPropertyName("binaryPayload")]
    public string? BinaryPayload { get; set; }
}

public sealed class BridgeResponse
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("type")]
    public string Type { get; set; } = "response";

    [JsonPropertyName("ok")]
    public bool Ok { get; set; }

    [JsonPropertyName("payload")]
    public JsonElement? Payload { get; set; }

    [JsonPropertyName("error")]
    public string? Error { get; set; }

    [JsonPropertyName("errorCode")]
    public string? ErrorCode { get; set; }
}

public sealed class BridgeEvent
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString("N");

    [JsonPropertyName("type")]
    public string Type { get; set; } = "event";

    [JsonPropertyName("channel")]
    public string Channel { get; set; } = "";

    [JsonPropertyName("method")]
    public string Method { get; set; } = "";

    [JsonPropertyName("payload")]
    public JsonElement? Payload { get; set; }

    [JsonPropertyName("binaryPayload")]
    public string? BinaryPayload { get; set; }
}
