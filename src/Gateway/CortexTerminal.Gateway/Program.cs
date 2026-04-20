using System.Text;
using CortexTerminal.Contracts.Auth;
using CortexTerminal.Contracts.Sessions;
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

app.MapPost("/api/sessions", (CreateSessionRequest request) =>
{
    if (!string.Equals(request.Runtime, "shell", StringComparison.Ordinal))
    {
        return Results.BadRequest("Only shell runtime is allowed in phase 1.");
    }

    return Results.Json(CreateSessionResult.Failure("no-worker-available"),
        statusCode: StatusCodes.Status503ServiceUnavailable);
}).RequireAuthorization();

app.Run();

public partial class Program;
