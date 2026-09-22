using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using System.Security.Claims;

namespace CortexTerminal.Gateway.WebSockets;

/// <summary>
/// ASP.NET Core middleware that accepts native WebSocket connections at /ws/terminal.
/// Validates JWT through the configured bearer pipeline, extracts sessionId, and delegates to TerminalWebSocketHandler.
/// </summary>
public class TerminalWebSocketMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<TerminalWebSocketMiddleware> _logger;

    public TerminalWebSocketMiddleware(RequestDelegate next, ILogger<TerminalWebSocketMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context, TerminalWebSocketHandler handler)
    {
        if (!context.Request.Path.StartsWithSegments("/ws/terminal"))
        {
            await _next(context);
            return;
        }

        if (!context.WebSockets.IsWebSocketRequest)
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            return;
        }

        var authResult = await context.AuthenticateAsync(JwtBearerDefaults.AuthenticationScheme);
        if (!authResult.Succeeded || authResult.Principal is null)
        {
            _logger.LogWarning(authResult.Failure, "Unauthorized WebSocket terminal connection");
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return;
        }

        // Extract sessionId
        var sessionId = context.Request.Query["sessionId"].FirstOrDefault();
        if (string.IsNullOrEmpty(sessionId))
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            return;
        }

        // Extract userId from claims
        var userId = authResult.Principal.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? authResult.Principal.FindFirstValue("sub")
            ?? authResult.Principal.FindFirstValue("nameid")
            ?? authResult.Principal.Identity?.Name
            ?? "unknown";

        // 可选能力协商（?caps=displaced,...）；旧客户端不带此参数，行为不变。
        var caps = context.Request.Query["caps"].FirstOrDefault() ?? string.Empty;

        // 增量重放游标（?since=<lastSeq>）：声明了 since 且 >0 的客户端走增量重放
        // （Worker 只回游标之后的块）；未声明/为 0 → 维持全量重放，旧客户端兼容。
        long since = 0;
        var sinceRaw = context.Request.Query["since"].FirstOrDefault();
        if (!string.IsNullOrEmpty(sinceRaw) && !long.TryParse(sinceRaw, out since))
        {
            since = 0;
        }

        _logger.LogInformation("WebSocket terminal connection: userId={UserId}, sessionId={SessionId}, caps={Caps}, since={Since}", userId, sessionId, caps, since);

        // Accept the WebSocket connection
        var ws = await context.WebSockets.AcceptWebSocketAsync();

        try
        {
            await handler.HandleAsync(ws, userId, sessionId, caps, since, context.RequestAborted);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "WebSocket handler error for session {SessionId}", sessionId);
        }
    }
}
