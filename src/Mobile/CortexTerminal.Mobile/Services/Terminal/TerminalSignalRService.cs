using System.Text.Json;
using CortexTerminal.Mobile.Bridge;
using CortexTerminal.Mobile.Services.Auth;
using Microsoft.AspNetCore.SignalR.Client;

namespace CortexTerminal.Mobile.Services.Terminal;

public sealed class TerminalSignalRService
{
    private readonly HubConnection _hubConnection;
    private readonly WebBridge _bridge;
    private readonly AuthService _authService;
    private readonly TerminalChunkBuffer _chunkBuffer;
    private readonly JsonSerializerOptions _jsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    private bool _handlersRegistered;

    public TerminalSignalRService(
        HubConnection hubConnection,
        WebBridge bridge,
        AuthService authService,
        TerminalChunkBuffer chunkBuffer)
    {
        _hubConnection = hubConnection;
        _bridge = bridge;
        _authService = authService;
        _chunkBuffer = chunkBuffer;
    }

    public async Task<BridgeResponse> HandleBridgeRequestAsync(BridgeMessage message, CancellationToken ct)
    {
        try
        {
            return message.Method switch
            {
                "connect" => await HandleConnectAsync(message, ct),
                "WriteInput" => await HandleWriteInputAsync(message, ct),
                "ResizeSession" => await HandleResizeAsync(message, ct),
                "CloseSession" => await HandleCloseAsync(message, ct),
                "DetachSession" => await HandleDetachAsync(message, ct),
                "ProbeLatency" => await HandleProbeLatencyAsync(message, ct),
                _ => new BridgeResponse { Ok = false, Error = $"Unknown signalr method: {message.Method}" },
            };
        }
        catch (Exception ex)
        {
            return new BridgeResponse { Ok = false, Error = ex.Message };
        }
    }

    private async Task EnsureHandlersRegisteredAsync()
    {
        if (_handlersRegistered) return;
        _handlersRegistered = true;

        _hubConnection.On<JsonElement>("StdoutChunk", chunk =>
        {
            var sessionId = chunk.GetProperty("sessionId").GetString()!;
            var stream = "stdout";
            var payloadBase64 = ExtractPayloadBase64(chunk);
            _chunkBuffer.BufferOrPush("StdoutChunk", sessionId, stream, payloadBase64);
        });

        _hubConnection.On<JsonElement>("StderrChunk", chunk =>
        {
            var sessionId = chunk.GetProperty("sessionId").GetString()!;
            var stream = "stderr";
            var payloadBase64 = ExtractPayloadBase64(chunk);
            _chunkBuffer.BufferOrPush("StderrChunk", sessionId, stream, payloadBase64);
        });

        _hubConnection.On<JsonElement>("SessionReattached", evt =>
        {
            _ = PushSessionEventAsync("SessionReattached", evt);
        });

        _hubConnection.On<JsonElement>("ReplayChunk", chunk =>
        {
            _ = PushChunkEventAsync("ReplayChunk", chunk);
        });

        _hubConnection.On<JsonElement>("ReplayCompleted", evt =>
        {
            _ = PushSessionEventAsync("ReplayCompleted", evt);
        });

        _hubConnection.On<JsonElement>("SessionExpired", evt =>
        {
            _ = PushSessionEventAsync("SessionExpired", evt);
        });

        _hubConnection.On<JsonElement>("SessionExited", evt =>
        {
            _ = PushSessionEventAsync("SessionExited", evt);
        });

        _hubConnection.On<JsonElement>("SessionStartFailed", evt =>
        {
            _ = PushSessionEventAsync("SessionStartFailed", evt);
        });

        _hubConnection.On<JsonElement>("LatencyProbeAck", probe =>
        {
            _ = _bridge.SendEventAsync(new BridgeEvent
            {
                Channel = "signalr",
                Method = "LatencyProbeAck",
                Payload = probe,
            });
        });
    }

    private async Task EnsureConnectedAsync(CancellationToken ct)
    {
        if (_hubConnection.State == HubConnectionState.Connected) return;

        await HubConnectionConnectionGate.EnsureConnectedAsync(
            () => _hubConnection.State,
            async token =>
            {
                await _hubConnection.StartAsync(token);
            },
            ct);
    }

    private async Task<BridgeResponse> HandleConnectAsync(BridgeMessage message, CancellationToken ct)
    {
        var sessionId = message.Payload?.GetProperty("sessionId").GetString() ?? "";

        await EnsureHandlersRegisteredAsync();
        await EnsureConnectedAsync(ct);

        var result = await _hubConnection.InvokeAsync<ReattachResultDto>(
            "ReattachSession",
            new { sessionId },
            ct);

        if (!result.IsSuccess)
        {
            return new BridgeResponse
            {
                Ok = true,
                Payload = JsonSerializer.Deserialize<JsonElement>(
                    JsonSerializer.Serialize(result, _jsonOptions)),
            };
        }

        return new BridgeResponse
        {
            Ok = true,
            Payload = JsonSerializer.Deserialize<JsonElement>(
                JsonSerializer.Serialize(result, _jsonOptions)),
        };
    }

    private async Task<BridgeResponse> HandleWriteInputAsync(BridgeMessage message, CancellationToken ct)
    {
        var sessionId = message.Payload?.GetProperty("sessionId").GetString() ?? "";
        var payloadBase64 = message.Payload?.GetProperty("payload").GetString() ?? "";

        await EnsureConnectedAsync(ct);
        await _hubConnection.InvokeAsync("WriteInput",
            new { sessionId, payload = payloadBase64 }, ct);

        return new BridgeResponse { Ok = true };
    }

    private async Task<BridgeResponse> HandleResizeAsync(BridgeMessage message, CancellationToken ct)
    {
        var sessionId = message.Payload?.GetProperty("sessionId").GetString() ?? "";
        var columns = message.Payload?.GetProperty("columns").GetInt32() ?? 80;
        var rows = message.Payload?.GetProperty("rows").GetInt32() ?? 24;

        await EnsureConnectedAsync(ct);
        await _hubConnection.InvokeAsync("ResizeSession",
            new { sessionId, columns, rows }, ct);

        return new BridgeResponse { Ok = true };
    }

    private async Task<BridgeResponse> HandleCloseAsync(BridgeMessage message, CancellationToken ct)
    {
        var sessionId = message.Payload?.GetProperty("sessionId").GetString() ?? "";

        await EnsureConnectedAsync(ct);
        await _hubConnection.InvokeAsync("CloseSession",
            new { sessionId }, ct);

        return new BridgeResponse { Ok = true };
    }

    private async Task<BridgeResponse> HandleDetachAsync(BridgeMessage message, CancellationToken ct)
    {
        var sessionId = message.Payload?.GetProperty("sessionId").GetString() ?? "";

        await EnsureConnectedAsync(ct);
        await _hubConnection.InvokeAsync("DetachSession",
            sessionId, ct);

        return new BridgeResponse { Ok = true };
    }

    private async Task<BridgeResponse> HandleProbeLatencyAsync(BridgeMessage message, CancellationToken ct)
    {
        var sessionId = message.Payload?.GetProperty("sessionId").GetString() ?? "";
        var probeId = message.Payload?.GetProperty("probeId").GetString() ?? "";

        await EnsureConnectedAsync(ct);
        await _hubConnection.InvokeAsync("ProbeLatency",
            new { sessionId, probeId }, ct);

        return new BridgeResponse { Ok = true };
    }

    private static string ExtractPayloadBase64(JsonElement chunk)
    {
        if (!chunk.TryGetProperty("payload", out var payloadProp)) return "";

        // SignalR JSON protocol encodes byte[] as base64 string
        if (payloadProp.ValueKind == JsonValueKind.String)
        {
            return payloadProp.GetString() ?? "";
        }

        // Array of numbers — convert to base64
        if (payloadProp.ValueKind == JsonValueKind.Array)
        {
            var bytes = new byte[payloadProp.GetArrayLength()];
            var i = 0;
            foreach (var item in payloadProp.EnumerateArray())
            {
                bytes[i++] = (byte)item.GetUInt32();
            }
            return Convert.ToBase64String(bytes);
        }

        return "";
    }

    private async Task PushSessionEventAsync(string method, JsonElement evt)
    {
        try
        {
            await _bridge.SendEventAsync(new BridgeEvent
            {
                Channel = "signalr",
                Method = method,
                Payload = evt,
            });
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[SignalRService] Push event error: {ex.Message}");
        }
    }

    private async Task PushChunkEventAsync(string method, JsonElement chunk)
    {
        try
        {
            var sessionId = chunk.GetProperty("sessionId").GetString()!;
            var stream = chunk.TryGetProperty("stream", out var s) ? s.GetString() ?? "stdout" : "stdout";
            var payloadBase64 = ExtractPayloadBase64(chunk);

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
            System.Diagnostics.Debug.WriteLine($"[SignalRService] Push chunk error: {ex.Message}");
        }
    }

    private record ReattachResultDto(bool IsSuccess, string? ErrorCode);
}
