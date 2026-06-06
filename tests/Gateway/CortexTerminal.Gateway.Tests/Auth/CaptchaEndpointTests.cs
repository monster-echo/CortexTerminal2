using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Auth;

public sealed class CaptchaEndpointTests : IClassFixture<GatewayApplicationFactory>
{
    private readonly GatewayApplicationFactory _factory;

    public CaptchaEndpointTests(GatewayApplicationFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Challenge_ReturnsOkWithCaptchaData()
    {
        using var client = _factory.CreateClient();

        using var response = await client.GetAsync("/api/auth/captcha/challenge");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var data = await response.Content.ReadFromJsonAsync<CaptchaChallengeResponse>();
        data.Should().NotBeNull();
        data!.Id.Should().NotBeNullOrWhiteSpace();
        data.BackgroundImage.Should().NotBeNullOrWhiteSpace();
        data.SliderImage.Should().NotBeNullOrWhiteSpace();
        data.Y.Should().BeGreaterThan(0).And.BeLessThan(180);

        // Verify the base64 images can be decoded as PNG
        var bgBytes = Convert.FromBase64String(data.BackgroundImage);
        bgBytes.Should().NotBeEmpty("background image should have content");

        var sliderBytes = Convert.FromBase64String(data.SliderImage);
        sliderBytes.Should().NotBeEmpty("slider image should have content");
    }

    [Fact]
    public async Task Challenge_MultipleCalls_ReturnUniqueIds()
    {
        using var client = _factory.CreateClient();

        var ids = new HashSet<string>();
        for (var i = 0; i < 5; i++)
        {
            using var response = await client.GetAsync("/api/auth/captcha/challenge");
            var data = await response.Content.ReadFromJsonAsync<CaptchaChallengeResponse>();
            ids.Add(data!.Id);
        }
        ids.Should().HaveCount(5, "each challenge should have a unique ID");
    }

    [Fact]
    public async Task Verify_WrongX_ReturnsBadRequest()
    {
        using var client = _factory.CreateClient();

        using var challengeResponse = await client.GetAsync("/api/auth/captcha/challenge");
        var challenge = await challengeResponse.Content.ReadFromJsonAsync<CaptchaChallengeResponse>();

        // Target X is random between ~50-250, X=0 is always outside the 5px tolerance
        using var verifyResponse = await client.PostAsJsonAsync("/api/auth/captcha/verify",
            new { Id = challenge!.Id, X = 0 });

        verifyResponse.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Verify_InvalidId_ReturnsBadRequest()
    {
        using var client = _factory.CreateClient();

        using var response = await client.PostAsJsonAsync("/api/auth/captcha/verify",
            new { Id = "nonexistent-id", X = 100 });

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Verify_InvalidRequest_ReturnsBadRequest()
    {
        using var client = _factory.CreateClient();

        // Empty ID
        using var response1 = await client.PostAsJsonAsync("/api/auth/captcha/verify",
            new { Id = "", X = 100 });
        response1.StatusCode.Should().Be(HttpStatusCode.BadRequest);

        // X <= 0
        using var response2 = await client.PostAsJsonAsync("/api/auth/captcha/verify",
            new { Id = "some-id", X = 0 });
        response2.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Verify_SameChallengeTwice_SecondFails()
    {
        using var client = _factory.CreateClient();

        using var challengeResponse = await client.GetAsync("/api/auth/captcha/challenge");
        var challenge = await challengeResponse.Content.ReadFromJsonAsync<CaptchaChallengeResponse>();

        // First attempt (will fail since X=0 is wrong, but consumes the challenge)
        using var verifyResponse1 = await client.PostAsJsonAsync("/api/auth/captcha/verify",
            new { Id = challenge!.Id, X = 0 });

        // Second attempt should also fail because ID was consumed
        using var verifyResponse2 = await client.PostAsJsonAsync("/api/auth/captcha/verify",
            new { Id = challenge.Id, X = 150 });

        verifyResponse2.StatusCode.Should().Be(HttpStatusCode.BadRequest,
            "challenge should be single-use");
    }

    private sealed record CaptchaChallengeResponse(string Id, string BackgroundImage, string SliderImage, int Y);
}
