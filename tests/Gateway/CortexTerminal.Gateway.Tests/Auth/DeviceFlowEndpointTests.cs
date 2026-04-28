using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FluentAssertions;
using CortexTerminal.Contracts.Auth;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Auth;

public sealed class DeviceFlowEndpointTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public DeviceFlowEndpointTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Start_ReturnsValidDeviceFlowStartResponse()
    {
        using var client = _factory.CreateClient();

        using var response = await client.PostAsync("/api/auth/device-flow", content: null);

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var payload = await response.Content.ReadFromJsonAsync<DeviceFlowStartResponse>();
        payload.Should().NotBeNull();
        payload!.DeviceCode.Should().NotBeNullOrWhiteSpace();
        payload.UserCode.Should().MatchRegex(@"^[A-Z0-9]{4}-[A-Z0-9]{4}$");
        payload.VerificationUri.Should().Contain("/activate");
        payload.ExpiresInSeconds.Should().Be(900);
        payload.PollIntervalSeconds.Should().Be(5);
    }

    [Fact]
    public async Task Poll_WithoutConfirmation_ReturnsAuthorizationPending()
    {
        using var client = _factory.CreateClient();

        // Start flow
        using var startResponse = await client.PostAsync("/api/auth/device-flow", content: null);
        var start = await startResponse.Content.ReadFromJsonAsync<DeviceFlowStartResponse>();

        // Poll before confirmation
        using var pollResponse = await client.PostAsJsonAsync("/api/auth/device-flow/token",
            new DeviceFlowPollRequest(start!.DeviceCode));

        pollResponse.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var error = await pollResponse.Content.ReadFromJsonAsync<JsonElement>();
        error.GetProperty("error").GetString().Should().Be("authorization_pending");
    }

    [Fact]
    public async Task Poll_WithInvalidDeviceCode_ReturnsInvalidRequest()
    {
        using var client = _factory.CreateClient();

        using var response = await client.PostAsJsonAsync("/api/auth/device-flow/token",
            new DeviceFlowPollRequest("nonexistent"));

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var error = await response.Content.ReadFromJsonAsync<JsonElement>();
        error.GetProperty("error").GetString().Should().Be("invalid_request");
    }

    [Fact]
    public async Task Verify_RejectsAnonymousRequests()
    {
        using var client = _factory.CreateClient();

        using var response = await client.PostAsJsonAsync("/api/auth/device-flow/verify",
            new DeviceFlowVerifyRequest("ABCD-EFGH"));

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Verify_WithInvalidUserCode_ReturnsError()
    {
        using var authClient = _factory.CreateAuthenticatedClient();

        using var response = await authClient.PostAsJsonAsync("/api/auth/device-flow/verify",
            new DeviceFlowVerifyRequest("NONEXISTENT"));

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var error = await response.Content.ReadFromJsonAsync<JsonElement>();
        error.GetProperty("error").GetString().Should().Be("invalid_code");
    }

    [Fact]
    public async Task FullFlow_Start_Verify_Poll_ReturnsToken()
    {
        using var client = _factory.CreateClient();
        using var authClient = _factory.CreateAuthenticatedClient();

        // 1. Start device flow
        using var startResponse = await client.PostAsync("/api/auth/device-flow", content: null);
        var start = await startResponse.Content.ReadFromJsonAsync<DeviceFlowStartResponse>();

        // 2. Verify user code (authenticated)
        using var verifyResponse = await authClient.PostAsJsonAsync("/api/auth/device-flow/verify",
            new DeviceFlowVerifyRequest(start!.UserCode));
        verifyResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        // 3. Poll for token
        using var pollResponse = await client.PostAsJsonAsync("/api/auth/device-flow/token",
            new DeviceFlowPollRequest(start.DeviceCode));
        pollResponse.StatusCode.Should().Be(HttpStatusCode.OK);

        var token = await pollResponse.Content.ReadFromJsonAsync<DeviceFlowTokenResponse>();
        token.Should().NotBeNull();
        token!.AccessToken.Should().NotBeNullOrWhiteSpace();
        token.ExpiresInSeconds.Should().Be(30 * 24 * 3600);
    }

    [Fact]
    public async Task Poll_AfterTokenIssued_ReturnsInvalidRequest()
    {
        using var client = _factory.CreateClient();
        using var authClient = _factory.CreateAuthenticatedClient();

        // Start + verify + poll to get token
        using var startResponse = await client.PostAsync("/api/auth/device-flow", content: null);
        var start = await startResponse.Content.ReadFromJsonAsync<DeviceFlowStartResponse>();

        await authClient.PostAsJsonAsync("/api/auth/device-flow/verify",
            new DeviceFlowVerifyRequest(start!.UserCode));

        await client.PostAsJsonAsync("/api/auth/device-flow/token",
            new DeviceFlowPollRequest(start.DeviceCode));

        // Poll again with same device code should fail
        using var secondPoll = await client.PostAsJsonAsync("/api/auth/device-flow/token",
            new DeviceFlowPollRequest(start.DeviceCode));

        secondPoll.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var error = await secondPoll.Content.ReadFromJsonAsync<JsonElement>();
        error.GetProperty("error").GetString().Should().Be("invalid_request");
    }

    [Fact]
    public async Task Refresh_WithValidToken_ReturnsNewToken()
    {
        using var authClient = _factory.CreateAuthenticatedClient();

        using var response = await authClient.PostAsync("/api/auth/refresh", content: null);

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var result = await response.Content.ReadFromJsonAsync<JsonElement>();
        result.GetProperty("accessToken").GetString().Should().NotBeNullOrWhiteSpace();
    }

    [Fact]
    public async Task Refresh_RejectsAnonymousRequests()
    {
        using var client = _factory.CreateClient();

        using var response = await client.PostAsync("/api/auth/refresh", content: null);

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
