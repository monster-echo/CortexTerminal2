using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Stats;
using CortexTerminal.Gateway.Workers;

namespace CortexTerminal.Gateway.WebSockets;

/// <summary>
/// Handles an individual native WebSocket connection for terminal I/O.
/// Orchestrates session reattachment, replay, and live terminal forwarding.
/// </summary>
public sealed class TerminalWebSocketHandler
{
    private readonly ISessionCoordinator _sessions;
    private readonly ReplayCoordinator _replayCoordinator;
    private readonly IWorkerCommandDispatcher _workerCommands;
    private readonly TimeProvider _timeProvider;
    private readonly IGatewayStatsService _stats;
    private readonly ILogger<TerminalWebSocketHandler> _logger;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
    };

    public TerminalWebSocketHandler(
        ISessionCoordinator sessions,
        ReplayCoordinator replayCoordinator,
        IWorkerCommandDispatcher workerCommands,
        ISessionLaunchCoordinator sessionLaunchCoordinator,
        TimeProvider timeProvider,
        IGatewayStatsService stats,
        ILogger<TerminalWebSocketHandler> logger)
    {
        _sessions = sessions;
        _replayCoordinator = replayCoordinator;
        _workerCommands = workerCommands;
        _ = sessionLaunchCoordinator;
        _timeProvider = timeProvider;
        _stats = stats;
        _logger = logger;
    }

    /// <summary>
    /// Main loop: read frames from the WebSocket and dispatch them.
    /// Also wires up output forwarding so the TerminalHub can push data to this WS connection.
    /// </summary>
    public async Task HandleAsync(WebSocket ws, string userId, string sessionId, CancellationToken cancellationToken)
    {
        // Validate the session exists and belongs to this user
        if (!_sessions.TryGetSession(sessionId, out var session))
        {
            await SendErrorAsync(ws, sessionId, "session-not-found", "Session not found.", cancellationToken);
            return;
        }

        if (session.UserId != userId)
        {
            await SendErrorAsync(ws, sessionId, "forbidden", "Session belongs to another user.", cancellationToken);
            return;
        }

        var connectionId = $"ws-{Guid.NewGuid():N}";

        // Register this WS connection for output forwarding
        TerminalWebSocketConnectionRegistry.Register(sessionId, connectionId, ws);
        TerminalWebSocketConnectionRegistry.RegisterUser(userId, connectionId, ws);
        _stats.ClientConnected();

        try
        {
            _replayCoordinator.BeginReplay(sessionId, connectionId);

            // Reattach the session (same logic as TerminalHub.ReattachSession)
            var reattachResult = await _sessions.ReattachSessionAsync(
                userId,
                new ReattachSessionRequest(sessionId),
                connectionId,
                _timeProvider.GetUtcNow(),
                cancellationToken);

            if (!reattachResult.IsSuccess)
            {
                _replayCoordinator.AbortReplay(sessionId);
                await SendErrorAsync(ws, sessionId, reattachResult.ErrorCode ?? "reattach-failed", "Failed to reattach session.", cancellationToken);
                return;
            }

            // Send replay
            await SendJsonAsync(ws, new WsReplayingFrame { SessionId = sessionId }, cancellationToken);

            _sessions.TryGetSession(sessionId, out var currentSession);
            var workerConnectionId = currentSession?.WorkerConnectionId;

            IReadOnlyList<TerminalChunk> snapshot = Array.Empty<TerminalChunk>();
            if (!string.IsNullOrEmpty(workerConnectionId))
            {
                try
                {
                    snapshot = await _workerCommands.RequestScrollbackAsync(workerConnectionId, sessionId, cancellationToken);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "RequestScrollback failed for WS session {SessionId}, sending empty replay.", sessionId);
                }
            }

            foreach (var chunk in snapshot)
            {
                await SendJsonAsync(ws, new WsReplayFrame
                {
                    SessionId = chunk.SessionId,
                    Stream = chunk.Stream,
                    Payload = Convert.ToBase64String(chunk.Payload)
                }, cancellationToken);
            }

            await SendJsonAsync(ws, new WsReplayCompletedFrame { SessionId = sessionId }, cancellationToken);

            await _replayCoordinator.FlushPendingAsync(
                sessionId,
                connectionId,
                chunk => SendJsonAsync(ws, new WsOutputFrame
                {
                    SessionId = chunk.SessionId,
                    Stream = chunk.Stream,
                    Payload = Convert.ToBase64String(chunk.Payload)
                }, cancellationToken),
                cancellationToken);

            await _sessions.MarkReplayCompleted(sessionId, connectionId);

            // Send "live" signal
            await SendJsonAsync(ws, new WsLiveFrame { SessionId = sessionId }, cancellationToken);

            var buffer = new byte[8192];
            while (!cancellationToken.IsCancellationRequested)
            {
                var receive = await ReceiveTextMessageAsync(ws, buffer, cancellationToken);
                if (receive is null)
                {
                    break;
                }

                var shouldContinue = await HandleClientFrameAsync(
                    ws,
                    receive,
                    sessionId,
                    cancellationToken);
                if (!shouldContinue)
                {
                    break;
                }
            }
        }
        catch (WebSocketException ex)
        {
            _logger.LogDebug(ex, "WebSocket connection closed unexpectedly for session {SessionId}", sessionId);
        }
        catch (OperationCanceledException)
        {
            // Normal shutdown
        }
        finally
        {
            _replayCoordinator.AbortReplay(sessionId);
            _stats.ClientDisconnected();
            TerminalWebSocketConnectionRegistry.Unregister(sessionId, connectionId);
            TerminalWebSocketConnectionRegistry.UnregisterUser(userId, connectionId);

            // Detach the session
            try
            {
                await _sessions.DetachSessionAsync(userId, sessionId, _timeProvider.GetUtcNow(), CancellationToken.None);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to detach session {SessionId} on WS close", sessionId);
            }
        }
    }

    private static async Task<string?> ReceiveTextMessageAsync(WebSocket ws, byte[] buffer, CancellationToken cancellationToken)
    {
        using var message = new MemoryStream();
        while (true)
        {
            var result = await ws.ReceiveAsync(new ArraySegment<byte>(buffer), cancellationToken);
            if (result.MessageType == WebSocketMessageType.Close)
            {
                return null;
            }

            if (result.MessageType != WebSocketMessageType.Text)
            {
                continue;
            }

            message.Write(buffer, 0, result.Count);
            if (result.EndOfMessage)
            {
                return Encoding.UTF8.GetString(message.ToArray());
            }
        }
    }

    private async Task<bool> HandleClientFrameAsync(WebSocket ws, string json, string sessionId, CancellationToken cancellationToken)
    {
        WsClientFrame? frame;
        try
        {
            frame = JsonSerializer.Deserialize<WsClientFrame>(json, JsonOptions);
        }
        catch (JsonException)
        {
            await SendErrorAsync(ws, sessionId, "invalid-frame", "Could not parse frame.", cancellationToken);
            return true;
        }

        if (frame is null)
        {
            return true;
        }

        if (!string.IsNullOrWhiteSpace(frame.SessionId) &&
            !string.Equals(frame.SessionId, sessionId, StringComparison.Ordinal))
        {
            await SendErrorAsync(ws, sessionId, "session-mismatch", "Frame sessionId does not match this connection.", cancellationToken);
            return true;
        }

        switch (frame.Type)
        {
            case "input":
                await HandleInputAsync(ws, frame, sessionId, cancellationToken);
                break;

            case "resize":
                await HandleResizeAsync(ws, frame, sessionId, cancellationToken);
                break;

            case "detach":
                await SendJsonAsync(ws, new WsDetachedFrame { SessionId = sessionId }, cancellationToken);
                if (ws.State == WebSocketState.Open)
                {
                    await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "detached", cancellationToken);
                }
                return false;

            case "close":
                await HandleCloseAsync(ws, frame, sessionId, cancellationToken);
                break;

            case "ping":
                await SendJsonAsync(ws, new WsPongFrame { Timestamp = frame.Timestamp ?? 0 }, cancellationToken);
                break;

            case "latencyProbe":
                await HandleLatencyProbeAsync(ws, frame, sessionId, cancellationToken);
                break;

            default:
                await SendErrorAsync(ws, sessionId, "unknown-frame-type", $"Unknown frame type: {frame.Type}", cancellationToken);
                break;
        }

        return true;
    }

    private async Task HandleInputAsync(WebSocket ws, WsClientFrame frame, string sessionId, CancellationToken cancellationToken)
    {
        if (!_sessions.TryGetSession(sessionId, out var session))
        {
            await SendErrorAsync(ws, sessionId, "session-not-found", "Session not found.", cancellationToken);
            return;
        }

        if (session.AttachmentState != SessionAttachmentState.Attached)
        {
            await SendErrorAsync(ws, sessionId, "not-attached", "Session is not attached.", cancellationToken);
            return;
        }

        byte[] payload;
        try
        {
            payload = frame.Payload is not null ? Convert.FromBase64String(frame.Payload) : [];
        }
        catch (FormatException)
        {
            await SendErrorAsync(ws, sessionId, "invalid-frame", "input payload must be base64.", cancellationToken);
            return;
        }

        await _workerCommands.WriteInputAsync(session.WorkerConnectionId, new WriteInputFrame(sessionId, payload), cancellationToken);
    }

    private async Task HandleResizeAsync(WebSocket ws, WsClientFrame frame, string sessionId, CancellationToken cancellationToken)
    {
        if (!_sessions.TryGetSession(sessionId, out var session))
        {
            await SendErrorAsync(ws, sessionId, "session-not-found", "Session not found.", cancellationToken);
            return;
        }

        if (frame.Columns is not { } cols || frame.Rows is not { } rows)
        {
            await SendErrorAsync(ws, sessionId, "invalid-frame", "resize requires columns and rows.", cancellationToken);
            return;
        }

        if (!TerminalSizeLimits.IsValid(cols, rows))
        {
            await SendErrorAsync(ws, sessionId, "invalid-frame", "resize dimensions are out of range.", cancellationToken);
            return;
        }

        await _workerCommands.ResizeSessionAsync(session.WorkerConnectionId, new ResizePtyRequest(sessionId, cols, rows), cancellationToken);
    }

    private async Task HandleCloseAsync(WebSocket ws, WsClientFrame frame, string sessionId, CancellationToken cancellationToken)
    {
        if (!_sessions.TryGetSession(sessionId, out var session))
        {
            return;
        }

        await _workerCommands.CloseSessionAsync(session.WorkerConnectionId, new CloseSessionRequest(sessionId), cancellationToken);
    }

    private async Task HandleLatencyProbeAsync(WebSocket ws, WsClientFrame frame, string sessionId, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(frame.ProbeId))
        {
            await SendErrorAsync(ws, sessionId, "invalid-frame", "latencyProbe requires probeId.", cancellationToken);
            return;
        }

        await SendJsonAsync(ws, new WsLatencyAckFrame
        {
            ProbeId = frame.ProbeId,
            ClientTime = frame.ClientTime ?? frame.Timestamp ?? 0,
            ServerTime = _timeProvider.GetUtcNow().ToUnixTimeMilliseconds()
        }, cancellationToken);
    }

    private async Task SendErrorAsync(WebSocket ws, string sessionId, string code, string message, CancellationToken cancellationToken)
    {
        await SendJsonAsync(ws, new WsErrorFrame { SessionId = sessionId, Code = code, Message = message }, cancellationToken);
    }

    private static async Task SendJsonAsync(WebSocket ws, object frame, CancellationToken cancellationToken)
    {
        var json = JsonSerializer.Serialize(frame, JsonOptions);
        var bytes = Encoding.UTF8.GetBytes(json);
        await ws.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, cancellationToken);
    }
}

/// <summary>
/// Registry to track active WebSocket connections by session ID,
/// so the TerminalHub can push output to the correct WebSocket.
/// </summary>
public static class TerminalWebSocketConnectionRegistry
{
    private static readonly ConcurrentDictionary<(string SessionId, string ConnectionId), WebSocket> _connections = new();
    private static readonly ConcurrentDictionary<(string UserId, string ConnectionId), WebSocket> _userConnections = new();

    public static void Register(string sessionId, string connectionId, WebSocket ws)
    {
        _connections[(sessionId, connectionId)] = ws;
    }

    public static void RegisterUser(string userId, string connectionId, WebSocket ws)
    {
        _userConnections[(userId, connectionId)] = ws;
    }

    public static void Unregister(string sessionId, string connectionId)
    {
        _connections.TryRemove((sessionId, connectionId), out _);
    }

    public static void UnregisterUser(string userId, string connectionId)
    {
        _userConnections.TryRemove((userId, connectionId), out _);
    }

    /// <summary>
    /// Try to send a frame to any active WebSocket connection for a given session.
    /// Returns true if the frame was sent successfully.
    /// </summary>
    public static async Task<bool> SendToSessionAsync(string sessionId, object frame, CancellationToken cancellationToken)
    {
        var json = JsonSerializer.Serialize(frame, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
        var bytes = Encoding.UTF8.GetBytes(json);
        var segment = new ArraySegment<byte>(bytes);

        var sent = false;
        foreach (var key in _connections.Keys.Where(k => k.SessionId == sessionId).ToList())
        {
            if (_connections.TryGetValue(key, out var ws) && ws.State == WebSocketState.Open)
            {
                try
                {
                    await ws.SendAsync(segment, WebSocketMessageType.Text, true, cancellationToken);
                    sent = true;
                }
                catch (WebSocketException)
                {
                    _connections.TryRemove(key, out _);
                }
            }
            else
            {
                _connections.TryRemove(key, out _);
            }
        }
        return sent;
    }

    /// <summary>
    /// Check if there is an active WebSocket connection for a given session.
    /// </summary>
    public static bool HasConnection(string sessionId)
    {
        return _connections.Keys.Any(k => k.SessionId == sessionId);
    }

    /// <summary>
    /// Send a frame to every active WebSocket connection owned by a given user.
    /// Used for user-scoped broadcasts like artifact change notifications.
    /// </summary>
    public static async Task SendToUserAsync(string userId, object frame, CancellationToken cancellationToken)
    {
        var json = JsonSerializer.Serialize(frame, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
        var bytes = Encoding.UTF8.GetBytes(json);
        var segment = new ArraySegment<byte>(bytes);

        foreach (var key in _userConnections.Keys.Where(k => k.UserId == userId).ToList())
        {
            if (_userConnections.TryGetValue(key, out var ws) && ws.State == WebSocketState.Open)
            {
                try
                {
                    await ws.SendAsync(segment, WebSocketMessageType.Text, true, cancellationToken);
                }
                catch (WebSocketException)
                {
                    _userConnections.TryRemove(key, out _);
                }
            }
            else
            {
                _userConnections.TryRemove(key, out _);
            }
        }
    }
}
