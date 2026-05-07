using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using Microsoft.AspNetCore.SignalR;

namespace CortexTerminal.Gateway.WebSockets;

/// <summary>
/// Handles an individual native WebSocket connection for terminal I/O.
/// Orchestrates session reattachment, replay, and live terminal forwarding.
/// </summary>
public sealed class TerminalWebSocketHandler
{
    private readonly ISessionCoordinator _sessions;
    private readonly IReplayCache _replayCache;
    private readonly IWorkerCommandDispatcher _workerCommands;
    private readonly ISessionLaunchCoordinator _sessionLaunchCoordinator;
    private readonly TimeProvider _timeProvider;
    private readonly ILogger<TerminalWebSocketHandler> _logger;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
    };

    public TerminalWebSocketHandler(
        ISessionCoordinator sessions,
        IReplayCache replayCache,
        IWorkerCommandDispatcher workerCommands,
        ISessionLaunchCoordinator sessionLaunchCoordinator,
        TimeProvider timeProvider,
        ILogger<TerminalWebSocketHandler> logger)
    {
        _sessions = sessions;
        _replayCache = replayCache;
        _workerCommands = workerCommands;
        _sessionLaunchCoordinator = sessionLaunchCoordinator;
        _timeProvider = timeProvider;
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

        try
        {
            // Reattach the session (same logic as TerminalHub.ReattachSession)
            var reattachResult = await _sessions.ReattachSessionAsync(
                userId,
                new ReattachSessionRequest(sessionId),
                connectionId,
                _timeProvider.GetUtcNow(),
                cancellationToken);

            if (!reattachResult.IsSuccess)
            {
                await SendErrorAsync(ws, sessionId, reattachResult.ErrorCode ?? "reattach-failed", "Failed to reattach session.", cancellationToken);
                return;
            }

            // Send replay
            await SendJsonAsync(ws, new WsReplayingFrame { SessionId = sessionId }, cancellationToken);

            await _replayCache.ReplayWhileLockedAsync(sessionId, async snapshot =>
            {
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
                _sessions.MarkReplayCompleted(sessionId, connectionId);
            }, cancellationToken);

            // Send "live" signal
            await SendJsonAsync(ws, new WsLiveFrame { SessionId = sessionId }, cancellationToken);

            // Now read frames from the client in a loop
            var buffer = new byte[8192];
            while (!cancellationToken.IsCancellationRequested)
            {
                var result = await ws.ReceiveAsync(new ArraySegment<byte>(buffer), cancellationToken);

                if (result.MessageType == WebSocketMessageType.Close)
                {
                    break;
                }

                if (result.MessageType == WebSocketMessageType.Text)
                {
                    var json = Encoding.UTF8.GetString(buffer, 0, result.Count);
                    await HandleClientFrameAsync(ws, json, userId, sessionId, connectionId, cancellationToken);
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
            TerminalWebSocketConnectionRegistry.Unregister(sessionId, connectionId);

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

    private async Task HandleClientFrameAsync(WebSocket ws, string json, string userId, string sessionId, string connectionId, CancellationToken cancellationToken)
    {
        WsClientFrame? frame;
        try
        {
            frame = JsonSerializer.Deserialize<WsClientFrame>(json, JsonOptions);
        }
        catch (JsonException)
        {
            await SendErrorAsync(ws, sessionId, "invalid-frame", "Could not parse frame.", cancellationToken);
            return;
        }

        if (frame is null)
        {
            return;
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
                // Client explicitly detaches — close the connection gracefully
                await SendJsonAsync(ws, new { type = "detached", sessionId }, cancellationToken);
                break;

            case "close":
                await HandleCloseAsync(ws, frame, sessionId, cancellationToken);
                break;

            case "ping":
                await SendJsonAsync(ws, new WsPongFrame { Timestamp = frame.Timestamp ?? 0 }, cancellationToken);
                break;

            default:
                await SendErrorAsync(ws, sessionId, "unknown-frame-type", $"Unknown frame type: {frame.Type}", cancellationToken);
                break;
        }
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

        var payload = frame.Payload is not null ? Convert.FromBase64String(frame.Payload) : [];
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

    public static void Register(string sessionId, string connectionId, WebSocket ws)
    {
        _connections[(sessionId, connectionId)] = ws;
    }

    public static void Unregister(string sessionId, string connectionId)
    {
        _connections.TryRemove((sessionId, connectionId), out _);
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
}
