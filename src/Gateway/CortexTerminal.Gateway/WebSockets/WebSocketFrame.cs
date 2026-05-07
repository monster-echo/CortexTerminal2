using System.Text.Json.Serialization;

namespace CortexTerminal.Gateway.WebSockets;

/// <summary>
/// JSON frame types for the native WebSocket terminal endpoint.
/// HarmonyOS and other non-SignalR clients use these frames over /ws/terminal.
/// </summary>

// --- Client → Server frames ---

public record WsInputFrame
{
    [JsonPropertyName("type")]
    public string Type => "input";
    [JsonPropertyName("sessionId")]
    public required string SessionId { get; init; }
    [JsonPropertyName("payload")]
    public required string Payload { get; init; } // base64
}

public record WsResizeFrame
{
    [JsonPropertyName("type")]
    public string Type => "resize";
    [JsonPropertyName("sessionId")]
    public required string SessionId { get; init; }
    [JsonPropertyName("columns")]
    public required int Columns { get; init; }
    [JsonPropertyName("rows")]
    public required int Rows { get; init; }
}

public record WsDetachFrame
{
    [JsonPropertyName("type")]
    public string Type => "detach";
    [JsonPropertyName("sessionId")]
    public required string SessionId { get; init; }
}

public record WsCloseFrame
{
    [JsonPropertyName("type")]
    public string Type => "close";
    [JsonPropertyName("sessionId")]
    public required string SessionId { get; init; }
}

public record WsPingFrame
{
    [JsonPropertyName("type")]
    public string Type => "ping";
    [JsonPropertyName("timestamp")]
    public required long Timestamp { get; init; }
}

// --- Server → Client frames ---

public record WsReplayingFrame
{
    [JsonPropertyName("type")]
    public string Type => "replaying";
    [JsonPropertyName("sessionId")]
    public required string SessionId { get; init; }
}

public record WsReplayFrame
{
    [JsonPropertyName("type")]
    public string Type => "replay";
    [JsonPropertyName("sessionId")]
    public required string SessionId { get; init; }
    [JsonPropertyName("stream")]
    public required string Stream { get; init; }
    [JsonPropertyName("payload")]
    public required string Payload { get; init; } // base64
}

public record WsReplayCompletedFrame
{
    [JsonPropertyName("type")]
    public string Type => "replayCompleted";
    [JsonPropertyName("sessionId")]
    public required string SessionId { get; init; }
}

public record WsOutputFrame
{
    [JsonPropertyName("type")]
    public string Type => "output";
    [JsonPropertyName("sessionId")]
    public required string SessionId { get; init; }
    [JsonPropertyName("stream")]
    public required string Stream { get; init; }
    [JsonPropertyName("payload")]
    public required string Payload { get; init; } // base64
}

public record WsLiveFrame
{
    [JsonPropertyName("type")]
    public string Type => "live";
    [JsonPropertyName("sessionId")]
    public required string SessionId { get; init; }
}

public record WsExpiredFrame
{
    [JsonPropertyName("type")]
    public string Type => "expired";
    [JsonPropertyName("sessionId")]
    public required string SessionId { get; init; }
    [JsonPropertyName("reason")]
    public required string Reason { get; init; }
}

public record WsExitedFrame
{
    [JsonPropertyName("type")]
    public string Type => "exited";
    [JsonPropertyName("sessionId")]
    public required string SessionId { get; init; }
    [JsonPropertyName("exitCode")]
    public required int ExitCode { get; init; }
    [JsonPropertyName("reason")]
    public required string Reason { get; init; }
}

public record WsErrorFrame
{
    [JsonPropertyName("type")]
    public string Type => "error";
    [JsonPropertyName("sessionId")]
    public required string SessionId { get; init; }
    [JsonPropertyName("code")]
    public required string Code { get; init; }
    [JsonPropertyName("message")]
    public required string Message { get; init; }
}

public record WsPongFrame
{
    [JsonPropertyName("type")]
    public string Type => "pong";
    [JsonPropertyName("timestamp")]
    public required long Timestamp { get; init; }
}

public record WsLatencyAckFrame
{
    [JsonPropertyName("type")]
    public string Type => "latencyAck";
    [JsonPropertyName("probeId")]
    public required string ProbeId { get; init; }
    [JsonPropertyName("clientTime")]
    public required long ClientTime { get; init; }
    [JsonPropertyName("serverTime")]
    public required long ServerTime { get; init; }
}

/// <summary>
/// Polymorphic deserialization wrapper for incoming client frames.
/// </summary>
public record WsClientFrame
{
    [JsonPropertyName("type")]
    public required string Type { get; init; }
    [JsonPropertyName("sessionId")]
    public string? SessionId { get; init; }
    [JsonPropertyName("payload")]
    public string? Payload { get; init; }
    [JsonPropertyName("columns")]
    public int? Columns { get; init; }
    [JsonPropertyName("rows")]
    public int? Rows { get; init; }
    [JsonPropertyName("timestamp")]
    public long? Timestamp { get; init; }
    [JsonPropertyName("probeId")]
    public string? ProbeId { get; init; }
}
