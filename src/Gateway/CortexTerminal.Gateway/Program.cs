using System.Text;
using CortexTerminal.Contracts.Auth;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

var signingKey = builder.Configuration["Auth:SigningKey"] ?? "gateway-auth-signing-key-minimum-32b";

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = "https://gateway.local/",
            ValidateAudience = true,
            ValidAudience = "cortex-terminal-gateway",
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(signingKey))
        };
    });

builder.Services.AddAuthorization();
builder.Services.AddSignalR().AddMessagePackProtocol();
builder.Services.AddSingleton<IWorkerRegistry, InMemoryWorkerRegistry>();
builder.Services.AddSingleton<ISessionCoordinator, InMemorySessionCoordinator>();
builder.Services.AddSingleton<IReplayCache>(_ => new ReplayCache(64 * 1024));
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddHostedService<DetachedSessionExpiryService>();

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/", () => Results.Ok(new { Name = "CortexTerminal.Gateway" }));

app.MapPost("/api/auth/device-flow", () =>
    Results.Ok(new DeviceFlowStartResponse(
        DeviceCode: Guid.NewGuid().ToString("N"),
        UserCode: "ABCD-EFGH",
        VerificationUri: "https://gateway.local/activate",
        ExpiresInSeconds: 900,
        PollIntervalSeconds: 5)));

app.MapPost("/api/sessions", async (CreateSessionRequest request, ISessionCoordinator sessions, System.Security.Claims.ClaimsPrincipal user, CancellationToken cancellationToken) =>
{
    if (!string.Equals(request.Runtime, "shell", StringComparison.Ordinal))
    {
        return Results.BadRequest("Only shell runtime is allowed in phase 1.");
    }

    var result = await sessions.CreateSessionAsync(user.Identity?.Name ?? "unknown", request, clientConnectionId: null, cancellationToken);
    return result.IsSuccess
        ? Results.Ok(result.Response)
        : Results.Json(CreateSessionResult.Failure("no-worker-available"),
            statusCode: StatusCodes.Status503ServiceUnavailable);
}).RequireAuthorization();

app.MapHub<TerminalHub>("/hubs/terminal");
app.MapHub<WorkerHub>("/hubs/worker");

app.Run();

public partial class Program;
