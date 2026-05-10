using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Tokens;

namespace CortexTerminal.Gateway.WebSockets;

/// <summary>
/// ASP.NET Core middleware that accepts native WebSocket connections at /ws/terminal.
/// Validates JWT from query string, extracts sessionId, and delegates to TerminalWebSocketHandler.
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

    public async Task InvokeAsync(HttpContext context, TerminalWebSocketHandler handler, IConfiguration configuration)
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

        // Extract JWT token from query string
        var token = context.Request.Query["token"].FirstOrDefault();
        if (string.IsNullOrEmpty(token))
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return;
        }

        // Validate JWT
        var signingKey = configuration["Auth:SigningKey"] ?? "gateway-auth-signing-key-minimum-32b";
        var validationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = "https://gateway.local/",
            ValidateAudience = true,
            ValidAudiences = ["corterm-gateway", "cortex-terminal-gateway"],
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(signingKey)),
            NameClaimType = ClaimTypes.NameIdentifier
        };

        ClaimsPrincipal user;
        try
        {
            var handler2 = new JwtSecurityTokenHandler();
            user = handler2.ValidateToken(token, validationParameters, out _);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Invalid JWT token on WebSocket connection");
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
        var userId = user.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? user.FindFirstValue(JwtRegisteredClaimNames.Sub)
            ?? user.Identity?.Name
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
