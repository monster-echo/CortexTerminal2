using System.Text.Json;
using CortexTerminal.Mobile.Bridge;

namespace CortexTerminal.Mobile.Services.Terminal;

public sealed class TerminalChunkBuffer
{
    private readonly WebBridge _bridge;
    private readonly List<BufferedEvent> _buffer = [];
    private readonly object _lock = new();
    private bool _isBuffering;
    private const int MaxBufferCount = 1000;

    public TerminalChunkBuffer(WebBridge bridge)
    {
        _bridge = bridge;
    }

    public void StartBuffering()
    {
        lock (_lock)
        {
            _isBuffering = true;
        }
    }

    public async Task StopBufferingAndFlushAsync()
    {
        List<BufferedEvent> snapshot;
        lock (_lock)
        {
            _isBuffering = false;
            snapshot = [.. _buffer];
            _buffer.Clear();
        }

        foreach (var evt in snapshot)
        {
            await _bridge.SendEventAsync(evt.ToBridgeEvent());
        }
    }

    public void BufferOrPush(string method, string sessionId, string stream, string payloadBase64)
    {
        bool shouldBuffer;
        lock (_lock)
        {
            shouldBuffer = _isBuffering;
            if (shouldBuffer)
            {
                if (_buffer.Count < MaxBufferCount)
                {
                    _buffer.Add(new BufferedEvent(method, sessionId, stream, payloadBase64));
                }
                return;
            }
        }

        // Not buffering — push directly (fire-and-forget to avoid blocking SignalR handler)
        _ = PushEventAsync(method, sessionId, stream, payloadBase64);
    }

    private async Task PushEventAsync(string method, string sessionId, string stream, string payloadBase64)
    {
        try
        {
            var dto = new { sessionId, stream, payload = payloadBase64 };
            var payload = JsonSerializer.Deserialize<JsonElement>(
                JsonSerializer.Serialize(dto));

            await _bridge.SendEventAsync(new BridgeEvent
            {
                Channel = "signalr",
                Method = method,
                Payload = payload,
            });
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[ChunkBuffer] Push error: {ex.Message}");
        }
    }

    private readonly record struct BufferedEvent(string Method, string SessionId, string Stream, string PayloadBase64)
    {
        public BridgeEvent ToBridgeEvent()
        {
            var dto = new { sessionId = SessionId, stream = Stream, payload = PayloadBase64 };
            var payload = JsonSerializer.Deserialize<JsonElement>(
                JsonSerializer.Serialize(dto));

            return new BridgeEvent
            {
                Channel = "signalr",
                Method = Method,
                Payload = payload,
            };
        }
    }
}
