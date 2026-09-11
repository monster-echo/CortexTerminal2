using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

namespace CortexTerminal.Gateway.WebSockets;

/// <summary>
/// 挤占通知的跨传输工具：向原生 WS 连接发 displaced 帧并关闭它。
/// TerminalHub（hub 连接被 WS 挤掉时）与 TerminalWebSocketHandler（WS 连接被挤掉时）共用。
/// 仅对声明了 displaced 能力（?caps=displaced）的连接发帧；旧客户端维持纯关闭行为。
/// </summary>
public static class DisplacedNotifier
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
    };

    public static async Task NotifyWebSocketAsync(string sessionId, string connectionId, ILogger logger)
    {
        var ws = TerminalWebSocketConnectionRegistry.GetConnection(sessionId, connectionId);
        if (ws is null || ws.State != WebSocketState.Open)
        {
            return;
        }
        try
        {
            var json = JsonSerializer.Serialize(
                new WsDisplacedFrame { SessionId = sessionId, Reason = "superseded" }, JsonOptions);
            var bytes = Encoding.UTF8.GetBytes(json);
            await ws.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, CancellationToken.None);
            await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "displaced", CancellationToken.None);
            logger.LogInformation("Displaced WS connection {ConnectionId} for session {SessionId}", connectionId, sessionId);
        }
        catch (WebSocketException ex)
        {
            logger.LogDebug(ex, "Failed to notify displaced connection {ConnectionId}", connectionId);
        }
    }
}
