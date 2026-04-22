using System.Text;
using CortexTerminal.Contracts.Auth;
using CortexTerminal.Contracts.Console;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

var signingKey = builder.Configuration["Auth:SigningKey"] ?? "gateway-auth-signing-key-minimum-32b";

string CreateAccessToken(string username)
{
    var claims = new[]
    {
        new Claim(JwtRegisteredClaimNames.Sub, username),
        new Claim(ClaimTypes.NameIdentifier, username),
        new Claim(ClaimTypes.Name, username),
        new Claim("oi_tkn_typ", "access_token")
    };
    var credentials = new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(signingKey)), SecurityAlgorithms.HmacSha256);
    var token = new JwtSecurityToken(
        issuer: "https://gateway.local/",
        audience: "cortex-terminal-gateway",
        claims: claims,
        expires: DateTime.UtcNow.AddMinutes(5),
        signingCredentials: credentials);
    token.Header["typ"] = "at+jwt";

    return new JwtSecurityTokenHandler().WriteToken(token);
}

static string GetUserId(ClaimsPrincipal user)
    => user.FindFirstValue(ClaimTypes.NameIdentifier)
        ?? user.FindFirstValue(JwtRegisteredClaimNames.Sub)
        ?? user.Identity?.Name
        ?? "unknown";

static object ToSessionSummaryResponse(SessionRecord session)
    => new
    {
        session.SessionId,
        session.WorkerId,
        Status = session.AttachmentState.ToString(),
        CreatedAt = session.CreatedAtUtc,
        LastActivityAt = session.LastActivityAtUtc,
        session.CreatedAtUtc,
        session.LastActivityAtUtc,
        session.AttachmentState,
        session.ExitCode,
        session.ExitReason
    };

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
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(signingKey)),
            NameClaimType = ClaimTypes.NameIdentifier
        };
    });

builder.Services.AddAuthorization();
builder.Services.AddSignalR().AddMessagePackProtocol();
builder.Services.AddSingleton<IWorkerRegistry, InMemoryWorkerRegistry>();
builder.Services.AddSingleton<ISessionCoordinator, InMemorySessionCoordinator>();
builder.Services.AddSingleton<IWorkerCommandDispatcher, SignalRWorkerCommandDispatcher>();
builder.Services.AddSingleton<IReplayCache>(_ => new ReplayCache(64 * 1024));
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddHostedService<DetachedSessionExpiryService>();

var app = builder.Build();

// Serve static files for the gateway console
app.UseDefaultFiles();
app.UseStaticFiles();

app.UseAuthentication();
app.UseAuthorization();


if (app.Environment.IsDevelopment())
{
    app.MapPost("/api/dev/login", (DevLoginRequest request) =>
        Results.Ok(new DevLoginResponse(CreateAccessToken(request.Username)))).AllowAnonymous();
}

app.MapPost("/api/auth/device-flow", () =>
    Results.Ok(new DeviceFlowStartResponse(
        DeviceCode: Guid.NewGuid().ToString("N"),
        UserCode: "ABCD-EFGH",
        VerificationUri: "https://gateway.local/activate",
        ExpiresInSeconds: 900,
        PollIntervalSeconds: 5)));

app.MapPost("/api/sessions", async (
    CreateSessionRequest request,
    ISessionCoordinator sessions,
    IWorkerCommandDispatcher workerCommands,
    System.Security.Claims.ClaimsPrincipal user,
    CancellationToken cancellationToken) =>
{
    if (!string.Equals(request.Runtime, "shell", StringComparison.Ordinal))
    {
        return Results.BadRequest("Only shell runtime is allowed in phase 1.");
    }

    var result = await sessions.CreateSessionAsync(GetUserId(user), request, clientConnectionId: null, cancellationToken);
    if (result.IsSuccess && result.Response is not null && sessions.TryGetSession(result.Response.SessionId, out var session))
    {
        try
        {
            await workerCommands.StartSessionAsync(session.WorkerConnectionId, new CortexTerminal.Contracts.Streaming.StartSessionCommand(session.SessionId, session.Columns, session.Rows), cancellationToken);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            sessions.MarkSessionStartFailed(session.SessionId, "worker-start-dispatch-failed");
            return Results.Json(CreateSessionResult.Failure("worker-start-dispatch-failed"),
                statusCode: StatusCodes.Status503ServiceUnavailable);
        }
    }

    return result.IsSuccess
        ? Results.Ok(result.Response)
        : Results.Json(CreateSessionResult.Failure("no-worker-available"),
            statusCode: StatusCodes.Status503ServiceUnavailable);
}).RequireAuthorization();

app.MapGet("/api/me/sessions", (ClaimsPrincipal user, ISessionCoordinator sessions) =>
{
    var userId = GetUserId(user);
    var summaries = sessions.GetSessionsForUser(userId)
        .OrderByDescending(session => session.LastActivityAtUtc)
        .Select(ToSessionSummaryResponse)
        .ToArray();

    return Results.Ok(summaries);
}).RequireAuthorization();

app.MapGet("/api/me/sessions/{sessionId}", (string sessionId, ClaimsPrincipal user, ISessionCoordinator sessions) =>
{
    if (!sessions.TryGetSession(sessionId, out var session))
    {
        return Results.NotFound();
    }

    if (session.UserId != GetUserId(user))
    {
        return Results.Forbid();
    }

    return Results.Ok(ToSessionSummaryResponse(session));
}).RequireAuthorization();

app.MapGet("/api/me/workers", (ClaimsPrincipal user, IWorkerRegistry workers, ISessionCoordinator sessions) =>
{
    var userId = GetUserId(user);
    var userSessions = sessions.GetSessionsForUser(userId);
    var summaries = workers.GetWorkersForUser(userId)
        .OrderBy(worker => worker.WorkerId)
        .Select(worker => new
        {
            worker.WorkerId,
            Name = worker.WorkerId,
            Address = worker.ConnectionId,
            IsOnline = true,
            LastSeenAtUtc = worker.LastSeenAtUtc,
            SessionCount = userSessions.Count(session => session.WorkerId == worker.WorkerId)
        })
        .ToArray();

    return Results.Ok(summaries);
}).RequireAuthorization();

app.MapGet("/api/me/workers/{workerId}", (string workerId, ClaimsPrincipal user, IWorkerRegistry workers, ISessionCoordinator sessions) =>
{
    var userId = GetUserId(user);
    if (!workers.TryGetWorker(workerId, out var worker))
    {
        return Results.NotFound();
    }

    if (worker.OwnerUserId != userId)
    {
        return Results.Forbid();
    }

    var hostedSessions = sessions.GetSessionsForUser(userId)
        .Where(session => session.WorkerId == workerId)
        .OrderByDescending(session => session.LastActivityAtUtc)
        .Select(ToSessionSummaryResponse)
        .ToArray();

    return Results.Ok(new
    {
        worker.WorkerId,
        Name = worker.WorkerId,
        Address = worker.ConnectionId,
        IsOnline = true,
        LastSeenAtUtc = worker.LastSeenAtUtc,
        SessionCount = hostedSessions.Length,
        Sessions = hostedSessions
    });
}).RequireAuthorization();

app.MapHub<TerminalHub>("/hubs/terminal");
app.MapHub<WorkerHub>("/hubs/worker");

// Fallback to index.html for client-side routing
app.MapFallbackToFile("index.html");

app.Run();

public partial class Program;
