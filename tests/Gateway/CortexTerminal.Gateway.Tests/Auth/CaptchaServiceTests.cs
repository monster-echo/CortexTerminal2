using CortexTerminal.Gateway.Auth;
using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Auth;

public sealed class CaptchaServiceTests
{
    private static CaptchaService CreateService(int tolerance = 5)
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Captcha:TolerancePixels"] = tolerance.ToString(),
                ["Auth:SigningKey"] = "gateway-auth-signing-key-minimum-32b",
            })
            .Build();
        return new CaptchaService(config);
    }

    [Fact]
    public void Generate_ReturnsValidChallenge()
    {
        var service = CreateService();
        var challenge = service.Generate();

        challenge.Should().NotBeNull();
        challenge.Id.Should().NotBeNullOrWhiteSpace();
        challenge.BackgroundImage.Should().NotBeNullOrWhiteSpace();
        challenge.SliderImage.Should().NotBeNullOrWhiteSpace();
        challenge.Y.Should().BeGreaterThan(0).And.BeLessThan(180);

        // Verify base64 data is valid by decoding
        var action = () => Convert.FromBase64String(challenge.BackgroundImage);
        action.Should().NotThrow("background image should be valid base64");
    }

    [Fact]
    public void Verify_CorrectPosition_ReturnsToken()
    {
        var service = CreateService();
        var challenge = service.Generate();

        // We don't know the exact target X, so try all positions within tolerance
        // The service generates a random target, so we need to find it
        // Actually we can't know it from outside. Let's test with a very large tolerance.
        var tolerantService = CreateService(tolerance: 300);
        var tolerantChallenge = tolerantService.Generate();

        var token = tolerantService.Verify(tolerantChallenge.Id, 0);
        token.Should().NotBeNull("any X within 300px tolerance should pass");

        // Token should look like a JWT (three base64 segments separated by dots)
        token!.Split('.').Should().HaveCount(3);
    }

    [Fact]
    public void Verify_WrongPosition_ReturnsNull()
    {
        // Use tolerance of 0 to ensure exact match needed
        var service = CreateService(tolerance: 0);
        var challenge = service.Generate();

        // Target X is random between ~50 and ~250, so 0 is almost certainly wrong
        var token = service.Verify(challenge.Id, 0);
        token.Should().BeNull("position 0 should not match a random target");
    }

    [Fact]
    public void ValidateToken_ValidToken_ReturnsTrue()
    {
        var service = CreateService(tolerance: 300);
        var challenge = service.Generate();
        var token = service.Verify(challenge.Id, 0);

        token.Should().NotBeNull();
        service.ValidateToken(token!).Should().BeTrue();
    }

    [Fact]
    public void ValidateToken_InvalidToken_ReturnsFalse()
    {
        var service = CreateService();
        service.ValidateToken("invalid.jwt.token").Should().BeFalse();
    }

    [Fact]
    public void ValidateToken_EmptyString_ReturnsFalse()
    {
        var service = CreateService();
        service.ValidateToken("").Should().BeFalse();
    }

    [Fact]
    public void Verify_SameIdTwice_ReturnsNullSecondTime()
    {
        var service = CreateService(tolerance: 300);
        var challenge = service.Generate();

        var token1 = service.Verify(challenge.Id, 0);
        token1.Should().NotBeNull();

        var token2 = service.Verify(challenge.Id, 0);
        token2.Should().BeNull("captcha should be single-use");
    }

    [Fact]
    public void Generate_MultipleChallenges_HaveUniqueIds()
    {
        var service = CreateService();
        var ids = new HashSet<string>();
        for (var i = 0; i < 10; i++)
        {
            var challenge = service.Generate();
            ids.Add(challenge.Id);
        }
        ids.Should().HaveCount(10, "each challenge should have a unique ID");
    }
}
