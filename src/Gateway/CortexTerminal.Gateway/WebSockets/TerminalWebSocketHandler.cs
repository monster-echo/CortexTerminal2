using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Stats;
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
    private readonly ReplayCoordinator _replayCoordinator;
    private readonly IWorkerCommandDispatcher _workerCommands;
    private readonly TimeProvider _timeProvider;
    private readonly IGatewayStatsService _stats;
    private readonly IHubContext<TerminalHub> _hubContext;
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
        IHubContext<TerminalHub> hubContext,
        ILogger<TerminalWebSocketHandler> logger)
    {
        _sessions = sessions;
        _replayCoordinator = replayCoordinator;
        _workerCommands = workerCommands;
        _ = sessionLaunchCoordinator;
        _timeProvider = timeProvider;
        _stats = stats;
        _hubContext = hubContext;
        _logger = logger;
    }

    /// <summary>
    /// Main loop: read frames from the WebSocket and dispatch them.
    /// Also wires up output forwarding so the TerminalHub can push data to this WS connection.
    /// [capabilities] 是客户端在连接 query（?caps=a,b）里声明的可选能力集，
    /// 当前仅 displaced：声明者被同 session 新连接挤掉时会收到 displaced 帧再关闭；
    /// 未声明者维持旧行为（连接被静默关闭），保证旧客户端兼容。
    /// [sinceSeq] 是客户端缓存的输出游标（?since=N，N>0 走增量重放；
    /// Worker 不支持或游标越界时回退全量重放，旧客户端不带 since 行为不变）。
    /// </summary>
    public async Task HandleAsync(WebSocket ws, string userId, string sessionId, string capabilities, long sinceSeq, CancellationToken cancellationToken)
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
        var supportsDisplaced = capabilities
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Contains("displaced", StringComparer.Ordinal);

        // Register this WS connection for output forwarding
        TerminalWebSocketConnectionRegistry.Register(sessionId, connectionId, ws);
        TerminalWebSocketConnectionRegistry.RegisterUser(userId, connectionId, ws);
        if (supportsDisplaced)
        {
            TerminalWebSocketConnectionRegistry.SetDisplacedCapable(connectionId);
        }
        _stats.ClientConnected();

        try
        {
            _replayCoordinator.BeginReplay(sessionId, connectionId);

            // 挤占通知目标：本次 reattach 前的附着连接（与 TerminalHub.ReattachSessionCore 同语义）。
            _sessions.TryGetSession(sessionId, out var priorSession);
            var displacedConnectionId = priorSession?.AttachedClientConnectionId;

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

            if (!string.IsNullOrEmpty(displacedConnectionId)
                && !string.Equals(displacedConnectionId, connectionId, StringComparison.Ordinal))
            {
                if (displacedConnectionId.StartsWith("ws-", StringComparison.Ordinal))
                {
                    _ = DisplacedNotifier.NotifyWebSocketAsync(sessionId, displacedConnectionId, _logger);
                }
                else
                {
                    // 旧附着是 SignalR hub 连接（如 MAUI 客户端）：走 hub 通道通知。
                    _ = _hubContext.Clients.Client(displacedConnectionId).SendAsync(
                        "SessionDisplaced",
                        new SessionDisplacedEvent(sessionId),
                        CancellationToken.None);
                }
            }

            // Send replay.
            // 增量重放（since>0）：向 Worker 请求游标之后的增量块，客户端无缝续屏
            // （不发 replaying 重置帧）；Worker 不支持（旧版 RPC 抛错）或 Gap
            // （游标早于保留窗口）时回退全量重放——对齐 TerminalHub 增量语义。
            _sessions.TryGetSession(sessionId, out var currentSession);
            var workerConnectionId = currentSession?.WorkerConnectionId;

            ScrollbackDelta? delta = null;
            if (sinceSeq > 0 && !string.IsNullOrEmpty(workerConnectionId))
            {
                try
                {
                    delta = await _workerCommands.RequestScrollbackSinceAsync(
                        workerConnectionId, sessionId, sinceSeq, cancellationToken);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "RequestScrollbackSince failed for WS session {SessionId}; falling back to full replay.", sessionId);
                }
            }

            if (delta is not null && !delta.Gap)
            {
                // Incremental: the client continues its painted screen — no reset frame.
                await SendJsonAsync(ws, new WsReplayDeltaStartedFrame { SessionId = sessionId }, cancellationToken);
                foreach (var item in delta.Items)
                {
                    await SendJsonAsync(ws, new WsReplayDeltaFrame
                    {
                        SessionId = item.Chunk.SessionId,
                        Stream = item.Chunk.Stream,
                        Payload = Convert.ToBase64String(item.Chunk.Payload),
                        Seq = item.Seq
                    }, cancellationToken);
                }
                await SendJsonAsync(ws, new WsReplayDeltaCompletedFrame { SessionId = sessionId, LastSeq = delta.LastSeq }, cancellationToken);
            }
            else
            {
                // Legacy full replay. Gap=true 时用 Worker 返回的保留缓冲做重置重放
                // （对齐 TerminalHub 回退语义）；否则按原路径整段拉取。
                await SendJsonAsync(ws, new WsReplayingFrame { SessionId = sessionId }, cancellationToken);

                IReadOnlyList<TerminalChunk> snapshot;
                if (delta is not null)
                {
                    snapshot = delta.Items.Select(i => i.Chunk).ToArray();
                }
                else if (!string.IsNullOrEmpty(workerConnectionId))
                {
                    try
                    {
                        snapshot = await _workerCommands.RequestScrollbackAsync(workerConnectionId, sessionId, cancellationToken);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning(ex, "RequestScrollback failed for WS session {SessionId}, sending empty replay.", sessionId);
                        snapshot = Array.Empty<TerminalChunk>();
                    }
                }
                else
                {
                    snapshot = Array.Empty<TerminalChunk>();
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
            }

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
            TerminalWebSocketConnectionRegistry.ClearDisplacedCapable(connectionId);

            // Detach the session（带 connectionId：被挤占后本连接不再有权拆附着）
            try
            {
                await _sessions.DetachSessionAsync(userId, sessionId, _timeProvider.GetUtcNow(), CancellationToken.None, clientConnectionId: connectionId);
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

    /// <summary>声明了 displaced 能力（连接时 ?caps=displaced）的连接 id 集合。</summary>
    private static readonly ConcurrentDictionary<string, byte> _displacedCapable = new();

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

    public static void SetDisplacedCapable(string connectionId) => _displacedCapable[connectionId] = 1;

    public static void ClearDisplacedCapable(string connectionId) => _displacedCapable.TryRemove(connectionId, out _);

    public static bool IsDisplacedCapable(string connectionId) => _displacedCapable.ContainsKey(connectionId);

    public static WebSocket? GetConnection(string sessionId, string connectionId) =>
        _connections.TryGetValue((sessionId, connectionId), out var ws) ? ws : null;

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
