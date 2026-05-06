using System.Net.Http.Headers;
using System.Reflection;
using System.Text;
using System.Text.Json;
using CortexTerminal.Contracts.Auth;
using CortexTerminal.Contracts.Console;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Audit;
using CortexTerminal.Gateway.Auth;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.HttpOverrides;
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
        expires: DateTime.UtcNow.AddDays(7),
        signingCredentials: credentials);
    token.Header["typ"] = "at+jwt";

    return new JwtSecurityTokenHandler().WriteToken(token);
}

IResult OAuthRedirect(string redirectUrl, string? token = null, string? error = null)
{
    var isCustomScheme = redirectUrl.Contains("://") && !redirectUrl.StartsWith("http", StringComparison.OrdinalIgnoreCase);
    if (isCustomScheme)
    {
        var sep = redirectUrl.Contains('?') ? "&" : "?";
        var qs = token is not null ? $"token={token}" : $"error={error}";
        return Results.Redirect($"{redirectUrl}{sep}{qs}");
    }
    if (error is not null)
        return Results.Redirect($"/sign-in?error={error}&redirect={Uri.EscapeDataString(redirectUrl)}");
    return Results.Redirect($"/sign-in?token={token}&redirect={Uri.EscapeDataString(redirectUrl)}");
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

static string CreateAppleClientSecret(AppleOAuthOptions options)
{
    var ecdsa = System.Security.Cryptography.ECDsa.Create();
    ecdsa.ImportFromPem(options.PrivateKey.Replace("\\n", "\n"));
    var tokenDescriptor = new Microsoft.IdentityModel.Tokens.SecurityTokenDescriptor
    {
        Issuer = options.TeamId,
        Subject = new System.Security.Claims.ClaimsIdentity(new[]
        {
            new System.Security.Claims.Claim("sub", options.ClientId),
        }),
        Expires = DateTime.UtcNow.AddHours(1),
        Audience = "https://appleid.apple.com",
        SigningCredentials = new Microsoft.IdentityModel.Tokens.SigningCredentials(
            new Microsoft.IdentityModel.Tokens.ECDsaSecurityKey(ecdsa),
            Microsoft.IdentityModel.Tokens.SecurityAlgorithms.EcdsaSha256)
    };
    var handler = new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler();
    var token = handler.CreateToken(tokenDescriptor) as System.IdentityModel.Tokens.Jwt.JwtSecurityToken;
    token!.Header["kid"] = options.KeyId;
    return handler.WriteToken(token);
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
builder.Services.AddSingleton<IWorkerCommandDispatcher, SignalRWorkerCommandDispatcher>();
builder.Services.AddSingleton<ISessionLaunchCoordinator, SessionLaunchCoordinator>();
builder.Services.AddSingleton<InMemoryDeviceFlowStore>();
builder.Services.AddSingleton<IReplayCache>(_ => new ReplayCache(64 * 1024));
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddHostedService<DetachedSessionExpiryService>();
builder.Services.AddHttpClient();
builder.Services.AddSingleton<OAuthStateService>();
builder.Services.AddSingleton<PhoneCodeStore>();
var phoneAuthOptions = new PhoneAuthOptions();
builder.Configuration.GetSection("PhoneAuth").Bind(phoneAuthOptions);
var appleOAuthOptions = new AppleOAuthOptions();
builder.Configuration.GetSection("AppleOAuth").Bind(appleOAuthOptions);

var connectionString = builder.Configuration["GATEWAY_POSTGRES_CONNECTION_STRING"]
    ?? builder.Configuration.GetConnectionString("DefaultConnection");
if (!string.IsNullOrEmpty(connectionString))
{
    builder.Services.AddDbContext<AppDbContext>(options =>
        options.UseNpgsql(connectionString));
    builder.Services.AddSingleton<IAuditLogStore, PostgresAuditLogStore>();
    builder.Services.AddSingleton<IWorkerRegistry, PostgresWorkerRegistry>();
    builder.Services.AddSingleton<ISessionCoordinator, PostgresSessionCoordinator>();
}
else
{
    builder.Services.AddSingleton<IAuditLogStore, InMemoryAuditLogStore>();
    builder.Services.AddSingleton<IWorkerRegistry, InMemoryWorkerRegistry>();
    builder.Services.AddSingleton<ISessionCoordinator, InMemorySessionCoordinator>();
}

var oAuthOptions = new OAuthOptions();
builder.Configuration.GetSection("Auth").Bind(oAuthOptions);

var app = builder.Build();

// Trust forwarded headers from reverse proxy (Caddy/Nginx)
var forwardedHeadersOptions = new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto
};
forwardedHeadersOptions.KnownIPNetworks.Clear();
forwardedHeadersOptions.KnownProxies.Clear();
app.UseForwardedHeaders(forwardedHeadersOptions);

// Auto-create database tables
if (!string.IsNullOrEmpty(connectionString))
{
    using (var scope = app.Services.CreateScope())
    {
        try
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            await db.Database.EnsureCreatedAsync();

            // EnsureCreatedAsync won't add new tables to an existing database.
            // Create the Workers table if it doesn't exist yet.
            await db.Database.ExecuteSqlRawAsync("""
                CREATE TABLE IF NOT EXISTS "Workers" (
                    "worker_id"           text        NOT NULL PRIMARY KEY,
                    "owner_user_id"       text        NULL,
                    "hostname"            text        NULL,
                    "operating_system"    text        NULL,
                    "architecture"        text        NULL,
                    "name"                text        NULL,
                    "version"             text        NULL,
                    "last_seen_at_utc"    timestamptz NOT NULL,
                    "first_connected_at_utc" timestamptz NULL,
                    "is_online"           boolean     NOT NULL
                );
                """);
        }
        catch (Exception ex)
        {
            var logger = scope.ServiceProvider.GetRequiredService<ILogger<Program>>();
            logger.LogWarning(ex, "Failed to connect to PostgreSQL database. Running without database persistence.");
        }
    }
}

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
    var isWorker = user.HasClaim("role", "worker");
    var accessToken = isWorker ? CreateWorkerAccessToken(userId) : CreateAccessToken(userId);
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

app.MapGet("/api/auth/callback/github", async (string? code, string? state, OAuthStateService stateService, IHttpClientFactory httpClientFactory, IAuditLogStore auditLog, IServiceProvider serviceProvider, HttpContext ctx) =>
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
    var githubLogin = userJson.TryGetProperty("login", out var loginProp) ? loginProp.GetString() : null;
    if (string.IsNullOrEmpty(githubLogin))
        return OAuthRedirect(redirectUrl, error: "github_user_failed");

    var email = userJson.TryGetProperty("email", out var emailProp) ? emailProp.GetString() : null;
    var displayName = userJson.TryGetProperty("name", out var nameProp) ? nameProp.GetString() : githubLogin;
    var avatarUrl = userJson.TryGetProperty("avatar_url", out var avatarProp) ? avatarProp.GetString() : null;

    // Auto-register / lookup user in database
    var dbUser = await EnsureUser(serviceProvider, githubLogin, email, displayName, avatarUrl, "github", githubLogin);
    if (dbUser is null || dbUser.Status == "disabled")
        return OAuthRedirect(redirectUrl, error: "account_disabled");

    var jwt = CreateAccessToken(dbUser.Username);
    auditLog.Record(new AuditLogEntry(
        Id: Guid.NewGuid().ToString("N"),
        Timestamp: DateTimeOffset.UtcNow,
        UserId: dbUser.Id,
        UserName: dbUser.Username,
        Action: "user.oauth_login",
        TargetEntity: "user",
        TargetId: dbUser.Id
    ));

    return OAuthRedirect(redirectUrl, token: jwt);
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

app.MapGet("/api/auth/callback/google", async (string? code, string? state, OAuthStateService stateService, IHttpClientFactory httpClientFactory, IAuditLogStore auditLog, IServiceProvider serviceProvider, HttpContext ctx) =>
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
    var googleSub = userJson.TryGetProperty("id", out var subProp) ? subProp.GetString() : null;
    var email = userJson.TryGetProperty("email", out var emailProp) ? emailProp.GetString() : null;
    var displayName = userJson.TryGetProperty("name", out var nameProp) ? nameProp.GetString() : email;
    var avatarUrl = userJson.TryGetProperty("picture", out var picProp) ? picProp.GetString() : null;

    if (string.IsNullOrEmpty(googleSub) && string.IsNullOrEmpty(email))
        return OAuthRedirect(redirectUrl, error: "google_user_failed");

    var username = displayName ?? email ?? googleSub!;
    var providerId = googleSub ?? email ?? "unknown";

    // Auto-register / lookup user in database
    var dbUser = await EnsureUser(serviceProvider, username, email, displayName, avatarUrl, "google", providerId);
    if (dbUser is null || dbUser.Status == "disabled")
        return OAuthRedirect(redirectUrl, error: "account_disabled");

    var jwt = CreateAccessToken(dbUser.Username);
    auditLog.Record(new AuditLogEntry(
        Id: Guid.NewGuid().ToString("N"),
        Timestamp: DateTimeOffset.UtcNow,
        UserId: dbUser.Id,
        UserName: dbUser.Username,
        Action: "user.oauth_login",
        TargetEntity: "user",
        TargetId: dbUser.Id
    ));

    return OAuthRedirect(redirectUrl, token: jwt);
}).AllowAnonymous();

// --- Phone Auth Endpoints ---

app.MapPost("/api/auth/phone/send-code", (SendCodeRequest request, PhoneCodeStore codeStore, IAuditLogStore auditLog, IServiceProvider serviceProvider, IWebHostEnvironment env) =>
{
    // Validate phone format: 11 digits
    if (string.IsNullOrEmpty(request.Phone) || request.Phone.Length != 11 || !request.Phone.All(char.IsDigit))
        return Results.BadRequest(new { error = "Invalid phone number" });

    string code;
    try
    {
        code = codeStore.Create(request.Phone);
    }
    catch (InvalidOperationException)
    {
        return Results.StatusCode(429);
    }

    if (env.IsDevelopment())
    {
        Console.WriteLine($"[PhoneAuth] Verification code for {request.Phone}: {code}");
    }
    else
    {
        if (string.IsNullOrEmpty(phoneAuthOptions.AccessKeyId))
            return Results.BadRequest(new { error = "Phone auth is not configured" });

        try
        {
            var client = new Aliyun.Acs.Core.DefaultAcsClient(
                Aliyun.Acs.Core.Profile.DefaultProfile.GetProfile(
                    phoneAuthOptions.RegionId, phoneAuthOptions.AccessKeyId, phoneAuthOptions.AccessKeySecret));
            var smsRequest = new Aliyun.Acs.Core.CommonRequest();
            smsRequest.Domain = "dysmsapi.aliyuncs.com";
            smsRequest.Version = "2017-05-25";
            smsRequest.Action = "SendSms";
            smsRequest.Method = Aliyun.Acs.Core.Http.MethodType.POST;
            smsRequest.AddQueryParameters("PhoneNumbers", request.Phone);
            smsRequest.AddQueryParameters("SignName", phoneAuthOptions.SignName);
            smsRequest.AddQueryParameters("TemplateCode", phoneAuthOptions.TemplateCode);
            smsRequest.AddQueryParameters("TemplateParam", $"{{\"code\":\"{code}\",\"time\":\"5\"}}");
            var response = client.GetCommonResponse(smsRequest);
            if (response.HttpResponse.Status != 200 || !response.Data.Contains("\"Code\":\"OK\""))
            {
                Console.WriteLine($"[PhoneAuth] SMS send failed: {response.Data}");
                return Results.StatusCode(500);
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[PhoneAuth] SMS send error: {ex.Message}");
            return Results.StatusCode(500);
        }
    }

    return Results.Ok(new { ok = true });
}).AllowAnonymous();

app.MapPost("/api/auth/phone/verify", async (VerifyCodeRequest request, PhoneCodeStore codeStore, IAuditLogStore auditLog, IServiceProvider serviceProvider) =>
{
    if (string.IsNullOrEmpty(request.Phone) || string.IsNullOrEmpty(request.Code))
        return Results.BadRequest(new { error = "Phone and code are required" });

    if (!codeStore.Verify(request.Phone, request.Code))
        return Results.BadRequest(new { error = "Invalid or expired verification code" });

    var providerId = $"+86{request.Phone}";
    var last4 = request.Phone[^4..];
    var username = $"phone_{last4}";
    var displayName = $"{request.Phone[..3]}****{last4}";

    var dbUser = await EnsureUser(serviceProvider, username, null, displayName, null, "phone", providerId);
    if (dbUser is null || dbUser.Status == "disabled")
        return Results.BadRequest(new { error = "Account disabled" });

    var jwt = CreateAccessToken(dbUser.Username);
    auditLog.Record(new AuditLogEntry(
        Id: Guid.NewGuid().ToString("N"),
        Timestamp: DateTimeOffset.UtcNow,
        UserId: dbUser.Id,
        UserName: dbUser.Username,
        Action: "user.phone_login",
        TargetEntity: "user",
        TargetId: dbUser.Id
    ));

    return Results.Ok(new { accessToken = jwt, username = dbUser.Username });
}).AllowAnonymous();

// --- Apple OAuth Endpoints ---

app.MapGet("/api/auth/apple", (string? redirect, OAuthStateService stateService, HttpContext ctx) =>
{
    if (string.IsNullOrEmpty(appleOAuthOptions.ClientId))
        return Results.BadRequest("Apple OAuth is not configured.");

    var state = stateService.Create(redirect ?? "/sessions");
    var callbackUrl = $"{ctx.Request.Scheme}://{ctx.Request.Host}/api/auth/callback/apple";
    var authorizeUrl = $"https://appleid.apple.com/auth/authorize?client_id={appleOAuthOptions.ClientId}&redirect_uri={Uri.EscapeDataString(callbackUrl)}&response_type=code&scope=name+email&response_mode=form_post&state={state}";
    return Results.Redirect(authorizeUrl);
}).AllowAnonymous();

app.MapPost("/api/auth/callback/apple", async (HttpContext ctx, OAuthStateService stateService, IHttpClientFactory httpClientFactory, IAuditLogStore auditLog, IServiceProvider serviceProvider) =>
{
    var code = ctx.Request.Form["code"].FirstOrDefault();
    var state = ctx.Request.Form["state"].FirstOrDefault();

    if (string.IsNullOrEmpty(code))
        return Results.Redirect("/sign-in?error=apple_denied");

    var redirectUrl = stateService.Consume(state ?? "") ?? "/sessions";

    var http = httpClientFactory.CreateClient();
    var callbackUrl = $"{ctx.Request.Scheme}://{ctx.Request.Host}/api/auth/callback/apple";

    // Generate Apple client secret JWT
    var clientSecret = CreateAppleClientSecret(appleOAuthOptions);

    // Exchange code for tokens
    var tokenResponse = await http.PostAsync("https://appleid.apple.com/auth/token", new FormUrlEncodedContent(
        new Dictionary<string, string>
        {
            ["client_id"] = appleOAuthOptions.ClientId,
            ["client_secret"] = clientSecret,
            ["code"] = code,
            ["redirect_uri"] = callbackUrl,
            ["grant_type"] = "authorization_code"
        }));

    if (!tokenResponse.IsSuccessStatusCode)
    {
        var errorBody = await tokenResponse.Content.ReadAsStringAsync();
        Console.WriteLine($"[AppleAuth] Token exchange failed: {errorBody}");
        return OAuthRedirect(redirectUrl, error: "apple_token_failed");
    }

    var tokenJson = await tokenResponse.Content.ReadFromJsonAsync<JsonElement>();
    var idToken = tokenJson.TryGetProperty("id_token", out var idTokenProp) ? idTokenProp.GetString() : null;
    if (string.IsNullOrEmpty(idToken))
        return OAuthRedirect(redirectUrl, error: "apple_id_token_missing");

    // Decode Apple ID token (JWT) to extract sub and email
    var appleSub = "";
    var appleEmail = "";
    try
    {
        var segments = idToken.Split('.');
        var payload = segments[1];
        payload = payload.Replace('-', '+').Replace('_', '/');
        switch (payload.Length % 4)
        {
            case 2: payload += "=="; break;
            case 3: payload += "="; break;
        }
        var json = System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(payload));
        using var doc = System.Text.Json.JsonDocument.Parse(json);
        appleSub = doc.RootElement.TryGetProperty("sub", out var subProp) ? subProp.GetString() ?? "" : "";
        appleEmail = doc.RootElement.TryGetProperty("email", out var emailProp) ? emailProp.GetString() ?? "" : "";
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[AppleAuth] ID token decode error: {ex.Message}");
        return OAuthRedirect(redirectUrl, error: "apple_id_token_invalid");
    }

    if (string.IsNullOrEmpty(appleSub))
        return OAuthRedirect(redirectUrl, error: "apple_user_failed");

    var username = !string.IsNullOrEmpty(appleEmail) ? appleEmail.Split('@')[0] : $"apple_{appleSub[..Math.Min(8, appleSub.Length)]}";
    var displayName = !string.IsNullOrEmpty(appleEmail) ? appleEmail : username;

    var dbUser = await EnsureUser(serviceProvider, username, appleEmail, displayName, null, "apple", appleSub);
    if (dbUser is null || dbUser.Status == "disabled")
        return OAuthRedirect(redirectUrl, error: "account_disabled");

    var jwt = CreateAccessToken(dbUser.Username);
    auditLog.Record(new AuditLogEntry(
        Id: Guid.NewGuid().ToString("N"),
        Timestamp: DateTimeOffset.UtcNow,
        UserId: dbUser.Id,
        UserName: dbUser.Username,
        Action: "user.oauth_login",
        TargetEntity: "user",
        TargetId: dbUser.Id
    ));

    return OAuthRedirect(redirectUrl, token: jwt);
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

// ---- Gateway Info ----
var gatewayVersion = Assembly.GetEntryAssembly()?.GetName().Version?.ToString() ?? "0.0.0";
var githubRepo = builder.Configuration["GitHub:Repo"] ?? "monster-echo/CortexTerminal2";
var latestVersionCache = new LatestVersionCache();

app.MapGet("/api/gateway/info", async (IConfiguration config) =>
{
    var latestWorkerVersion = await latestVersionCache.GetLatestAsync(
        $"https://api.github.com/repos/{githubRepo}/releases",
        "worker-v");
    var latestGatewayVersion = await latestVersionCache.GetLatestAsync(
        $"https://api.github.com/repos/{githubRepo}/releases",
        "gateway-v");

    return Results.Ok(new
    {
        Version = gatewayVersion,
        LatestWorkerVersion = latestWorkerVersion,
        LatestGatewayVersion = latestGatewayVersion
    });
}).RequireAuthorization();

app.MapGet("/api/me/workers", async (ClaimsPrincipal user, IWorkerRegistry workers) =>
{
    var userId = GetUserId(user);
    var allWorkers = await workers.GetAllWorkersForUserAsync(userId);

    var summaries = allWorkers
        .Select(w => new
        {
            w.WorkerId,
            Name = w.Name ?? w.Hostname ?? w.WorkerId,
            w.Hostname,
            w.OperatingSystem,
            w.Architecture,
            w.Version,
            Address = (string?)null,
            w.IsOnline,
            w.LastSeenAtUtc,
            SessionCount = 0
        })
        .ToArray();

    return Results.Ok(summaries);
}).RequireAuthorization();

app.MapGet("/api/me/workers/{workerId}", async (string workerId, ClaimsPrincipal user, IWorkerRegistry workers, ISessionCoordinator sessions) =>
{
    var userId = GetUserId(user);
    var allWorkers = await workers.GetAllWorkersForUserAsync(userId);
    var workerRecord = allWorkers.FirstOrDefault(w => w.WorkerId == workerId);

    if (workerRecord is null)
    {
        return Results.NotFound();
    }

    var hostedSessions = sessions.GetSessionsForUser(userId)
        .Where(session => session.WorkerId == workerId)
        .OrderByDescending(session => session.LastActivityAtUtc)
        .Select(ToSessionSummaryResponse)
        .ToArray();

    return Results.Ok(new
    {
        workerRecord.WorkerId,
        Name = workerRecord.Name ?? workerRecord.Hostname ?? workerRecord.WorkerId,
        workerRecord.Hostname,
        workerRecord.OperatingSystem,
        workerRecord.Architecture,
        workerRecord.Version,
        Address = (string?)null,
        workerRecord.IsOnline,
        workerRecord.LastSeenAtUtc,
        SessionCount = hostedSessions.Length,
        Sessions = hostedSessions
    });
}).RequireAuthorization();

app.MapPost("/api/me/workers/{workerId}/upgrade", async (string workerId, ClaimsPrincipal user, IWorkerRegistry workers, IWorkerCommandDispatcher dispatcher) =>
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

    var latestVersion = await latestVersionCache.GetLatestAsync(
        $"https://api.github.com/repos/{githubRepo}/releases",
        "worker-v");

    if (string.IsNullOrEmpty(latestVersion))
    {
        return Results.BadRequest(new { error = "Could not determine latest worker version." });
    }

    // Build RID from worker metadata
    var os = worker.Metadata?.OperatingSystem;
    var arch = worker.Metadata?.Architecture ?? "X64";
    var ridOs = os != null && os.Contains("Darwin", StringComparison.OrdinalIgnoreCase) ? "osx"
              : os != null && os.Contains("Windows", StringComparison.OrdinalIgnoreCase) ? "win"
              : "linux";
    var ridArch = arch.Equals("Arm64", StringComparison.OrdinalIgnoreCase) ? "arm64" : "x64";
    var rid = $"{ridOs}-{ridArch}";
    var ext = ridOs == "win" ? "zip" : "tar.gz";
    var assetName = $"cortex-{rid}.{ext}";
    var githubProxy = builder.Configuration["GitHub:Proxy"] ?? "https://proxy.0x2a.top";
    var downloadUrl = $"{githubProxy}/https://github.com/{githubRepo}/releases/latest/download/{assetName}";

    await dispatcher.UpgradeWorkerAsync(worker.ConnectionId, new UpgradeWorkerCommand(latestVersion, downloadUrl), CancellationToken.None);
    return Results.Ok(new { message = "Upgrade command sent.", TargetVersion = latestVersion });
}).RequireAuthorization();

app.MapHub<TerminalHub>("/hubs/terminal");
app.MapHub<WorkerHub>("/hubs/worker");

// --- User Management Endpoints ---

app.MapGet("/api/users", async (ClaimsPrincipal user, IServiceProvider serviceProvider) =>
{
    var userId = GetUserId(user);
    if (!await IsAdmin(serviceProvider, userId))
        return Results.Forbid();

    await using var scope = serviceProvider.CreateAsyncScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    var users = await db.Users
        .OrderBy(u => u.CreatedAtUtc)
        .Select(u => new
        {
            u.Id,
            Name = u.DisplayName ?? u.Username,
            u.Email,
            u.Role,
            u.Status,
            u.AvatarUrl
        })
        .ToListAsync();

    return Results.Ok(users);
}).RequireAuthorization();

app.MapPost("/api/users/invite", async (InviteUserRequest request, ClaimsPrincipal user, IServiceProvider serviceProvider, IAuditLogStore auditLog) =>
{
    var userId = GetUserId(user);
    if (!await IsAdmin(serviceProvider, userId))
        return Results.Forbid();

    await using var scope = serviceProvider.CreateAsyncScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

    var newUser = new User
    {
        Id = Guid.NewGuid().ToString("N"),
        Username = request.Email,
        Email = request.Email,
        DisplayName = request.Email,
        Role = request.Role ?? "user",
        Status = "active",
        AuthProvider = "invited",
        CreatedAtUtc = DateTimeOffset.UtcNow,
        UpdatedAtUtc = DateTimeOffset.UtcNow
    };

    db.Users.Add(newUser);
    await db.SaveChangesAsync();

    auditLog.Record(new AuditLogEntry(
        Id: Guid.NewGuid().ToString("N"),
        Timestamp: DateTimeOffset.UtcNow,
        UserId: userId,
        UserName: userId,
        Action: "user.invite",
        TargetEntity: "user",
        TargetId: newUser.Id
    ));

    return Results.Ok(new
    {
        newUser.Id,
        Name = newUser.DisplayName,
        newUser.Email,
        newUser.Role,
        newUser.Status,
        newUser.AvatarUrl
    });
}).RequireAuthorization();

app.MapPatch("/api/users/{userId}", async (string userId, UpdateUserRequest request, ClaimsPrincipal user, IServiceProvider serviceProvider, IAuditLogStore auditLog) =>
{
    var currentUserId = GetUserId(user);
    if (!await IsAdmin(serviceProvider, currentUserId))
        return Results.Forbid();

    await using var scope = serviceProvider.CreateAsyncScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

    var targetUser = await db.Users.FindAsync(userId);
    if (targetUser is null)
        return Results.NotFound();

    if (request.Role is not null)
        targetUser.Role = request.Role;
    if (request.Status is not null)
        targetUser.Status = request.Status;
    targetUser.UpdatedAtUtc = DateTimeOffset.UtcNow;

    await db.SaveChangesAsync();

    auditLog.Record(new AuditLogEntry(
        Id: Guid.NewGuid().ToString("N"),
        Timestamp: DateTimeOffset.UtcNow,
        UserId: currentUserId,
        UserName: currentUserId,
        Action: "user.update",
        TargetEntity: "user",
        TargetId: userId
    ));

    return Results.Ok();
}).RequireAuthorization();

app.MapDelete("/api/users/{userId}", async (string userId, ClaimsPrincipal user, IServiceProvider serviceProvider, IAuditLogStore auditLog) =>
{
    var currentUserId = GetUserId(user);
    if (!await IsAdmin(serviceProvider, currentUserId))
        return Results.Forbid();

    await using var scope = serviceProvider.CreateAsyncScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

    var targetUser = await db.Users.FindAsync(userId);
    if (targetUser is null)
        return Results.NotFound();

    db.Users.Remove(targetUser);
    await db.SaveChangesAsync();

    auditLog.Record(new AuditLogEntry(
        Id: Guid.NewGuid().ToString("N"),
        Timestamp: DateTimeOffset.UtcNow,
        UserId: currentUserId,
        UserName: currentUserId,
        Action: "user.delete",
        TargetEntity: "user",
        TargetId: userId
    ));

    return Results.Ok();
}).RequireAuthorization();

// Fallback to index.html for client-side routing
app.MapFallbackToFile("index.html");

app.Run();

// --- Helper Methods ---

static async Task<User?> EnsureUser(IServiceProvider serviceProvider, string username, string? email, string? displayName, string? avatarUrl, string authProvider, string authProviderId)
{
    var scopeFactory = serviceProvider.GetRequiredService<IServiceScopeFactory>();
    using var scope = scopeFactory.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

    // Try find by auth provider
    var existing = await db.Users.FirstOrDefaultAsync(u => u.AuthProvider == authProvider && u.AuthProviderId == authProviderId);
    if (existing is not null)
    {
        // Update profile info from latest OAuth response
        existing.Email = email ?? existing.Email;
        existing.DisplayName = displayName ?? existing.DisplayName;
        existing.AvatarUrl = avatarUrl ?? existing.AvatarUrl;
        existing.UpdatedAtUtc = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync();
        return existing;
    }

    // Try find by email to link providers for the same person
    if (!string.IsNullOrEmpty(email))
    {
        var existingByEmail = await db.Users.FirstOrDefaultAsync(u => u.Email == email);
        if (existingByEmail is not null)
        {
            existingByEmail.AuthProvider = authProvider;
            existingByEmail.AuthProviderId = authProviderId;
            existingByEmail.DisplayName = displayName ?? existingByEmail.DisplayName;
            existingByEmail.AvatarUrl = avatarUrl ?? existingByEmail.AvatarUrl;
            existingByEmail.UpdatedAtUtc = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync();
            return existingByEmail;
        }
    }

    // Resolve username collision by appending provider suffix
    var finalUsername = username;
    if (await db.Users.AnyAsync(u => u.Username == username))
    {
        finalUsername = $"{username}_{authProvider}";
        if (await db.Users.AnyAsync(u => u.Username == finalUsername))
        {
            finalUsername = $"{username}_{authProviderId}";
        }
    }

    // First-user-is-admin
    var userCount = await db.Users.CountAsync();
    var role = userCount == 0 ? "admin" : "user";

    var newUser = new User
    {
        Id = Guid.NewGuid().ToString("N"),
        Username = finalUsername,
        Email = email,
        DisplayName = displayName ?? username,
        AvatarUrl = avatarUrl,
        Role = role,
        Status = "active",
        AuthProvider = authProvider,
        AuthProviderId = authProviderId,
        CreatedAtUtc = DateTimeOffset.UtcNow,
        UpdatedAtUtc = DateTimeOffset.UtcNow
    };

    db.Users.Add(newUser);
    await db.SaveChangesAsync();
    return newUser;
}

static async Task<bool> IsAdmin(IServiceProvider serviceProvider, string userId)
{
    // If no database, all authenticated users are treated as admin
    try
    {
        var scopeFactory = serviceProvider.GetRequiredService<IServiceScopeFactory>();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var user = await db.Users.FindAsync(userId);
        // Also check by username since JWT contains username as NameIdentifier
        if (user is null)
            user = await db.Users.FirstOrDefaultAsync(u => u.Username == userId);
        return user?.Role == "admin";
    }
    catch (InvalidOperationException)
    {
        // No DbContext registered (no database), treat all as admin
        return true;
    }
}

public record InviteUserRequest(string Email, string? Role);
public record UpdateUserRequest(string? Role, string? Status);
record SendCodeRequest(string Phone);
record VerifyCodeRequest(string Phone, string Code);

internal sealed class LatestVersionCache
{
    private readonly HttpClient _http = new()
    {
        DefaultRequestHeaders =
        {
            UserAgent = { new System.Net.Http.Headers.ProductInfoHeaderValue("CortexTerminal", "1.0") }
        }
    };

    private string? _workerLatest;
    private string? _gatewayLatest;
    private DateTimeOffset _lastRefresh = DateTimeOffset.MinValue;
    private readonly SemaphoreSlim _lock = new(1, 1);
    private static readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(30);

    public async Task<string?> GetLatestAsync(string releasesUrl, string tagPrefix)
    {
        await RefreshIfNeededAsync(releasesUrl);
        return tagPrefix == "worker-v" ? _workerLatest : _gatewayLatest;
    }

    private async Task RefreshIfNeededAsync(string releasesUrl)
    {
        if (DateTimeOffset.UtcNow - _lastRefresh < CacheDuration) return;

        await _lock.WaitAsync();
        try
        {
            if (DateTimeOffset.UtcNow - _lastRefresh < CacheDuration) return;

            try
            {
                using var resp = await _http.GetAsync(releasesUrl);
                if (!resp.IsSuccessStatusCode) return;

                using var doc = await JsonDocument.ParseAsync(await resp.Content.ReadAsStreamAsync());
                foreach (var release in doc.RootElement.EnumerateArray())
                {
                    if (!release.TryGetProperty("tag_name", out var tagEl)) continue;
                    var tag = tagEl.GetString() ?? "";
                    var version = tag.StartsWith("worker-v") ? tag["worker-v".Length..]
                        : tag.StartsWith("gateway-v") ? tag["gateway-v".Length..]
                        : null;
                    if (version is null) continue;

                    if (tag.StartsWith("worker-v") && _workerLatest is null)
                        _workerLatest = version;
                    else if (tag.StartsWith("gateway-v") && _gatewayLatest is null)
                        _gatewayLatest = version;

                    if (_workerLatest is not null && _gatewayLatest is not null) break;
                }

                _lastRefresh = DateTimeOffset.UtcNow;
            }
            catch
            {
                // GitHub API unavailable — keep cached values
            }
        }
        finally
        {
            _lock.Release();
        }
    }
}

public partial class Program;
