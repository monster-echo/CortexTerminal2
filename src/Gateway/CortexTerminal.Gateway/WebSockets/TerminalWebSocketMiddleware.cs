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

        _logger.LogInformation("WebSocket terminal connection: userId={UserId}, sessionId={SessionId}", userId, sessionId);

        // Accept the WebSocket connection
        var ws = await context.WebSockets.AcceptWebSocketAsync();

        try
        {
            await handler.HandleAsync(ws, userId, sessionId, context.RequestAborted);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "WebSocket handler error for session {SessionId}", sessionId);
        }
    }
}
