using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using CortexTerminal.Contracts.Auth;
using CortexTerminal.Contracts.Console;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Audit;
using CortexTerminal.Gateway.Auth;
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

string CreateWorkerAccessToken(string username)
{
    var claims = new[]
    {
        new Claim(JwtRegisteredClaimNames.Sub, username),
        new Claim(ClaimTypes.NameIdentifier, username),
        new Claim(ClaimTypes.Name, username),
        new Claim("oi_tkn_typ", "access_token"),
        new Claim("role", "worker")
    };
    var credentials = new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(signingKey)), SecurityAlgorithms.HmacSha256);
    var token = new JwtSecurityToken(
        issuer: "https://gateway.local/",
        audience: "cortex-terminal-gateway",
        claims: claims,
        expires: DateTime.UtcNow.AddDays(30),
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

        options.Events = new JwtBearerEvents
        {
            OnMessageReceived = context =>
            {
                var accessToken = context.Request.Query["access_token"];
                var path = context.HttpContext.Request.Path;

                if (!string.IsNullOrEmpty(accessToken)
                    && (path.StartsWithSegments("/hubs/terminal")
                        || path.StartsWithSegments("/hubs/worker")))
                {
                    context.Token = accessToken;
                }

                return Task.CompletedTask;
            }
        };
    });

builder.Services.AddAuthorization();
builder.Services.AddControllers();
builder.Services.AddSignalR().AddMessagePackProtocol();
builder.Services.AddSingleton<IWorkerRegistry, InMemoryWorkerRegistry>();
builder.Services.AddSingleton<ISessionCoordinator, InMemorySessionCoordinator>();
builder.Services.AddSingleton<IWorkerCommandDispatcher, SignalRWorkerCommandDispatcher>();
builder.Services.AddSingleton<ISessionLaunchCoordinator, SessionLaunchCoordinator>();
builder.Services.AddSingleton<IAuditLogStore, InMemoryAuditLogStore>();
builder.Services.AddSingleton<InMemoryDeviceFlowStore>();
builder.Services.AddSingleton<IReplayCache>(_ => new ReplayCache(64 * 1024));
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddHostedService<DetachedSessionExpiryService>();
builder.Services.AddHttpClient();
builder.Services.AddSingleton<OAuthStateService>();

var oAuthOptions = new OAuthOptions();
builder.Configuration.GetSection("Auth").Bind(oAuthOptions);

var app = builder.Build();

// Serve static files for the gateway console
app.UseDefaultFiles();
app.UseStaticFiles();

app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();


if (app.Environment.IsDevelopment())
{
    app.MapPost("/api/dev/login", (DevLoginRequest request, IAuditLogStore auditLog) =>
    {
        auditLog.Record(new AuditLogEntry(
            Id: Guid.NewGuid().ToString("N"),
            Timestamp: DateTimeOffset.UtcNow,
            UserId: request.Username,
            UserName: request.Username,
            Action: "user.login",
            TargetEntity: "user",
            TargetId: request.Username
        ));
        return Results.Ok(new DevLoginResponse(CreateAccessToken(request.Username)));
    }).AllowAnonymous();
}

var verificationUri = builder.Configuration["Auth:VerificationUri"] ?? "https://gateway.ct.rwecho.top/activate";

app.MapPost("/api/auth/device-flow", (InMemoryDeviceFlowStore store) =>
{
    var request = store.Create();
    return Results.Ok(new DeviceFlowStartResponse(
        DeviceCode: request.DeviceCode,
        UserCode: request.UserCode,
        VerificationUri: verificationUri,
        ExpiresInSeconds: 900,
        PollIntervalSeconds: 5));
}).AllowAnonymous();

app.MapPost("/api/auth/device-flow/token", (DeviceFlowPollRequest pollRequest, InMemoryDeviceFlowStore store) =>
{
    if (!store.TryGetByDeviceCode(pollRequest.DeviceCode, out var pending) || pending is null)
    {
        return Results.Json(new { error = "invalid_request" }, statusCode: 400);
    }

    if (pending.ExpiresAtUtc < DateTimeOffset.UtcNow)
    {
        store.Remove(pending.DeviceCode);
        return Results.Json(new { error = "expired_token" }, statusCode: 400);
    }

    if (!pending.Confirmed)
    {
        return Results.Json(new { error = "authorization_pending" }, statusCode: 400);
    }

    store.Remove(pending.DeviceCode);
    var accessToken = CreateWorkerAccessToken(pending.OwnerUserId ?? pending.OwnerUsername ?? "unknown");

    return Results.Ok(new DeviceFlowTokenResponse(
        AccessToken: accessToken,
        RefreshToken: "",
        ExpiresInSeconds: 30 * 24 * 3600));
}).AllowAnonymous();

app.MapPost("/api/auth/device-flow/verify", (DeviceFlowVerifyRequest verifyRequest, ClaimsPrincipal user, InMemoryDeviceFlowStore store) =>
{
    var userId = GetUserId(user);
    var username = user.Identity?.Name ?? userId;

    if (!store.Confirm(verifyRequest.UserCode, userId, username))
    {
        return Results.Json(new { error = "invalid_code" }, statusCode: 400);
    }

    return Results.Ok(new { confirmed = true });
}).RequireAuthorization();

app.MapPost("/api/auth/refresh", (ClaimsPrincipal user) =>
{
    var userId = GetUserId(user);
    var accessToken = CreateWorkerAccessToken(userId);
    return Results.Ok(new { accessToken });
}).RequireAuthorization();

// --- OAuth Login Endpoints ---

app.MapGet("/api/auth/github", (string? redirect, OAuthStateService stateService, HttpContext ctx) =>
{
    if (string.IsNullOrEmpty(oAuthOptions.GitHub.ClientId))
        return Results.BadRequest("GitHub OAuth is not configured.");

    var state = stateService.Create(redirect ?? "/sessions");
    var callbackUrl = $"{ctx.Request.Scheme}://{ctx.Request.Host}/api/auth/callback/github";
    var authorizeUrl = $"https://github.com/login/oauth/authorize?client_id={oAuthOptions.GitHub.ClientId}&redirect_uri={Uri.EscapeDataString(callbackUrl)}&state={state}&scope=read:user+user:email";
    return Results.Redirect(authorizeUrl);
}).AllowAnonymous();

app.MapGet("/api/auth/callback/github", async (string? code, string? state, OAuthStateService stateService, IHttpClientFactory httpClientFactory, IAuditLogStore auditLog, HttpContext ctx) =>
{
    if (string.IsNullOrEmpty(code))
        return Results.Redirect("/sign-in?error=github_denied");

    var redirectUrl = stateService.Consume(state ?? "") ?? "/sessions";

    var http = httpClientFactory.CreateClient();
    // Exchange code for access token
    var tokenResponse = await http.PostAsync("https://github.com/login/oauth/access_token", new FormUrlEncodedContent(
        new Dictionary<string, string>
        {
            ["client_id"] = oAuthOptions.GitHub.ClientId,
            ["client_secret"] = oAuthOptions.GitHub.ClientSecret,
            ["code"] = code
        }));
    tokenResponse.EnsureSuccessStatusCode();

    var tokenBody = await tokenResponse.Content.ReadAsStringAsync();
    var tokenParams = System.Web.HttpUtility.ParseQueryString(tokenBody);
    var accessToken = tokenParams["access_token"];
    if (string.IsNullOrEmpty(accessToken))
        return Results.Redirect($"/sign-in?error=github_token_failed&redirect={Uri.EscapeDataString(redirectUrl)}");

    // Get user info
    var userRequest = new HttpRequestMessage(HttpMethod.Get, "https://api.github.com/user");
    userRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
    userRequest.Headers.UserAgent.ParseAdd("CortexTerminal-Gateway");
    var userResponse = await http.SendAsync(userRequest);
    userResponse.EnsureSuccessStatusCode();

    var userJson = await userResponse.Content.ReadFromJsonAsync<JsonElement>();
    var username = userJson.TryGetProperty("login", out var loginProp) ? loginProp.GetString() : null;
    if (string.IsNullOrEmpty(username))
        return Results.Redirect($"/sign-in?error=github_user_failed&redirect={Uri.EscapeDataString(redirectUrl)}");

    var jwt = CreateAccessToken(username);
    auditLog.Record(new AuditLogEntry(
        Id: Guid.NewGuid().ToString("N"),
        Timestamp: DateTimeOffset.UtcNow,
        UserId: username,
        UserName: username,
        Action: "user.oauth_login",
        TargetEntity: "user",
        TargetId: username
    ));

    return Results.Redirect($"/sign-in?token={jwt}&redirect={Uri.EscapeDataString(redirectUrl)}");
}).AllowAnonymous();

app.MapGet("/api/auth/google", (string? redirect, OAuthStateService stateService, HttpContext ctx) =>
{
    if (string.IsNullOrEmpty(oAuthOptions.Google.ClientId))
        return Results.BadRequest("Google OAuth is not configured.");

    var state = stateService.Create(redirect ?? "/sessions");
    var callbackUrl = $"{ctx.Request.Scheme}://{ctx.Request.Host}/api/auth/callback/google";
    var authorizeUrl = $"https://accounts.google.com/o/oauth2/v2/auth?client_id={oAuthOptions.Google.ClientId}&redirect_uri={Uri.EscapeDataString(callbackUrl)}&response_type=code&scope=openid+profile+email&state={state}";
    return Results.Redirect(authorizeUrl);
}).AllowAnonymous();

app.MapGet("/api/auth/callback/google", async (string? code, string? state, OAuthStateService stateService, IHttpClientFactory httpClientFactory, IAuditLogStore auditLog, HttpContext ctx) =>
{
    if (string.IsNullOrEmpty(code))
        return Results.Redirect("/sign-in?error=google_denied");

    var redirectUrl = stateService.Consume(state ?? "") ?? "/sessions";

    var http = httpClientFactory.CreateClient();
    // Exchange code for access token
    var callbackUrl = $"{ctx.Request.Scheme}://{ctx.Request.Host}/api/auth/callback/google";
    var tokenResponse = await http.PostAsync("https://oauth2.googleapis.com/token", new FormUrlEncodedContent(
        new Dictionary<string, string>
        {
            ["client_id"] = oAuthOptions.Google.ClientId,
            ["client_secret"] = oAuthOptions.Google.ClientSecret,
            ["code"] = code,
            ["redirect_uri"] = callbackUrl,
            ["grant_type"] = "authorization_code"
        }));
    tokenResponse.EnsureSuccessStatusCode();

    var tokenJson = await tokenResponse.Content.ReadFromJsonAsync<JsonElement>();
    var accessToken = tokenJson.TryGetProperty("access_token", out var atProp) ? atProp.GetString() : null;
    if (string.IsNullOrEmpty(accessToken))
        return Results.Redirect($"/sign-in?error=google_token_failed&redirect={Uri.EscapeDataString(redirectUrl)}");

    // Get user info
    var userRequest = new HttpRequestMessage(HttpMethod.Get, "https://www.googleapis.com/oauth2/v2/userinfo");
    userRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
    var userResponse = await http.SendAsync(userRequest);
    userResponse.EnsureSuccessStatusCode();

    var userJson = await userResponse.Content.ReadFromJsonAsync<JsonElement>();
    var username = userJson.TryGetProperty("name", out var nameProp) ? nameProp.GetString() : null;
    if (string.IsNullOrEmpty(username))
        username = userJson.TryGetProperty("email", out var emailProp) ? emailProp.GetString() : null;
    if (string.IsNullOrEmpty(username))
        return Results.Redirect($"/sign-in?error=google_user_failed&redirect={Uri.EscapeDataString(redirectUrl)}");

    var jwt = CreateAccessToken(username);
    auditLog.Record(new AuditLogEntry(
        Id: Guid.NewGuid().ToString("N"),
        Timestamp: DateTimeOffset.UtcNow,
        UserId: username,
        UserName: username,
        Action: "user.oauth_login",
        TargetEntity: "user",
        TargetId: username
    ));

    return Results.Redirect($"/sign-in?token={jwt}&redirect={Uri.EscapeDataString(redirectUrl)}");
}).AllowAnonymous();

app.MapPost("/api/sessions", async (
    CreateSessionRequest request,
    ISessionLaunchCoordinator sessionLaunchCoordinator,
    IAuditLogStore auditLog,
    System.Security.Claims.ClaimsPrincipal user,
    CancellationToken cancellationToken) =>
{
    if (!string.Equals(request.Runtime, "shell", StringComparison.Ordinal))
    {
        return Results.BadRequest("Only shell runtime is allowed in phase 1.");
    }

    var userId = GetUserId(user);
    var result = await sessionLaunchCoordinator.CreateSessionAsync(
        userId,
        request,
        clientConnectionId: null,
        cancellationToken);

    if (result.IsSuccess)
    {
        auditLog.Record(new AuditLogEntry(
            Id: Guid.NewGuid().ToString("N"),
            Timestamp: DateTimeOffset.UtcNow,
            UserId: userId,
            UserName: userId,
            Action: "session.create",
            TargetEntity: "session",
            TargetId: result.Response!.SessionId
        ));
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
