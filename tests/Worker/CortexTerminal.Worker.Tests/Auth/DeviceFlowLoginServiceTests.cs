using System.Net;
using System.Net.Http.Json;
using CortexTerminal.Contracts.Auth;
using CortexTerminal.Worker.Auth;
using FluentAssertions;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.TestHost;
using Xunit;

namespace CortexTerminal.Worker.Tests.Auth;

public sealed class DeviceFlowLoginServiceTests : IAsyncDisposable
{
    private readonly TestServer _server;
    private readonly string _tempDir;
    private readonly FileWorkerTokenStore _tokenStore;

    public DeviceFlowLoginServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"login-test-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
        _tokenStore = new FileWorkerTokenStore(_tempDir);

        var builder = WebApplication.CreateBuilder();
        builder.WebHost.UseTestServer();
        var app = builder.Build();

        // Simulate Gateway device flow endpoints
        app.MapPost("/api/auth/device-flow", () =>
            Results.Ok(new DeviceFlowStartResponse(
                DeviceCode: "test-device-code",
                UserCode: "ABCD-1234",
                VerificationUri: "https://gateway.ct.rwecho.top/activate",
                ExpiresInSeconds: 900,
                PollIntervalSeconds: 1)));

        app.MapPost("/api/auth/device-flow/token", async (HttpContext context) =>
        {
            var body = await context.Request.ReadFromJsonAsync<DeviceFlowPollRequest>();
            if (body?.DeviceCode == "test-device-code")
            {
                await context.Response.WriteAsJsonAsync(new DeviceFlowTokenResponse(
                    AccessToken: "test-access-token",
                    RefreshToken: "",
                    ExpiresInSeconds: 2592000));
                return;
            }

            context.Response.StatusCode = 400;
            await context.Response.WriteAsJsonAsync(new { error = "invalid_request" });
        });

        app.MapPost("/api/auth/refresh", () =>
            Results.Ok(new { accessToken = "refreshed-token" }));

        app.StartAsync().GetAwaiter().GetResult();
        _server = app.GetTestServer();
    }

    public async ValueTask DisposeAsync()
    {
        _server.Dispose();
        if (Directory.Exists(_tempDir))
            Directory.Delete(_tempDir, true);
        await ValueTask.CompletedTask;
    }

    [Fact]
    public async Task LoginAsync_SavesTokenToStore()
    {
        var httpClient = _server.CreateClient();
        var service = new DeviceFlowLoginService(httpClient, _tokenStore);

        await service.LoginAsync(CancellationToken.None);

        var saved = await _tokenStore.GetAccessTokenAsync(CancellationToken.None);
        saved.Should().Be("test-access-token");
    }

    [Fact]
    public async Task RefreshTokenAsync_WithValidToken_ReturnsNewToken()
    {
        var httpClient = _server.CreateClient();
        var service = new DeviceFlowLoginService(httpClient, _tokenStore);

        var result = await service.RefreshTokenAsync("old-token", CancellationToken.None);

        result.Should().Be("refreshed-token");
        var saved = await _tokenStore.GetAccessTokenAsync(CancellationToken.None);
        saved.Should().Be("refreshed-token");
    }

    [Fact]
    public async Task RefreshTokenAsync_WhenServerUnavailable_ReturnsNull()
    {
        using var disconnectedClient = new HttpClient { BaseAddress = new Uri("http://localhost:1") };
        var service = new DeviceFlowLoginService(disconnectedClient, _tokenStore);

        var result = await service.RefreshTokenAsync("old-token", CancellationToken.None);

        result.Should().BeNull();
    }
}
