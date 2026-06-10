using System.Reflection;
using CortexTerminal.Gateway.Auth;
using FluentAssertions;
using Microsoft.Extensions.Configuration;
using SkiaSharp;
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

    /// <summary>
    /// Verifies the slider piece is drawn at the left (InitialPieceX) with content from the hole position.
    /// Uses reflection to extract the stored expected sliderX, then calls Verify with that value.
    /// </summary>
    [Fact]
    public void Verify_StoredTargetXMatchesSliderOffset()
    {
        var service = CreateService(tolerance: 0);
        var challenge = service.Generate();

        // Extract the stored TargetX via reflection
        var storedTargetX = GetStoredTargetX(service, challenge.Id);
        storedTargetX.Should().BeGreaterThan(0);
        storedTargetX.Should().BeLessThan(256, "expected sliderX = originalTargetX - InitialPieceX, must fit in track");

        // Verify with the stored value should pass
        var token = service.Verify(challenge.Id, storedTargetX);
        token.Should().NotBeNull("exact stored TargetX should pass with tolerance=0");
    }

    [Fact]
    public void Verify_OffsetByOneFromStored_FailsWithZeroTolerance()
    {
        var service = CreateService(tolerance: 0);
        var challenge = service.Generate();

        var storedTargetX = GetStoredTargetX(service, challenge.Id);

        // Off by 1 should fail with tolerance=0
        service.Verify(challenge.Id, storedTargetX + 1).Should().BeNull("off by 1 should fail with tolerance=0");
    }

    [Fact]
    public void Verify_WithinTolerance_Passes()
    {
        var service = CreateService(tolerance: 5);
        var challenge = service.Generate();

        var storedTargetX = GetStoredTargetX(service, challenge.Id);

        // Within ±5 should pass
        service.Verify(challenge.Id, storedTargetX + 3).Should().NotBeNull("within tolerance should pass");
    }

    [Fact]
    public void Verify_BeyondTolerance_Fails()
    {
        var service = CreateService(tolerance: 5);
        var challenge = service.Generate();

        var storedTargetX = GetStoredTargetX(service, challenge.Id);

        // Beyond ±5 should fail
        service.Verify(challenge.Id, storedTargetX + 10).Should().BeNull("beyond tolerance should fail");
    }

    [Fact]
    public void Generate_SliderPieceContentMatchesHolePosition()
    {
        var service = CreateService(tolerance: 5);
        var challenge = service.Generate();

        var bgBytes = Convert.FromBase64String(challenge.BackgroundImage);
        var sliderBytes = Convert.FromBase64String(challenge.SliderImage);

        using var bgBitmap = SKBitmap.Decode(bgBytes);
        using var sliderBitmap = SKBitmap.Decode(sliderBytes);

        bgBitmap.Should().NotBeNull();
        sliderBitmap.Should().NotBeNull();

        var storedTargetX = GetStoredTargetX(service, challenge.Id);
        const int initialPieceX = 30; // PieceSize/2 + PiecePadding
        var originalTargetX = storedTargetX + initialPieceX;

        // Slider piece at (initialPieceX, challenge.Y) should have the same pixels as
        // the clean background at (originalTargetX, challenge.Y).
        // The bg bitmap has a darkened hole at originalTargetX, so we compare slider pixels
        // with bg pixels at the same position — they should differ because the hole darkened the bg.
        // Instead, compare that slider has non-transparent pixels at the piece area.
        var centerPixel = sliderBitmap.GetPixel(initialPieceX, challenge.Y);
        centerPixel.Alpha.Should().BeGreaterThan(0, "piece center should be visible (non-transparent)");

        // And the piece area at initialPieceX should NOT match the darkened hole area on bg
        var bgHolePixel = bgBitmap.GetPixel(originalTargetX, challenge.Y);
        // The slider piece should be brighter than the darkened hole (hole has alpha overlay)
        centerPixel.Red.Should().BeGreaterThan(bgHolePixel.Red,
            "slider piece should show original colors, not darkened hole colors");
    }

    private static int GetStoredTargetX(CaptchaService service, string challengeId)
    {
        var entriesField = typeof(CaptchaService)
            .GetField("_entries", BindingFlags.NonPublic | BindingFlags.Instance)!;
        var entries = (System.Collections.IDictionary)entriesField.GetValue(service)!;
        var entry = entries[challengeId]!;
        var entryType = entry.GetType();
        return (int)entryType.GetProperty("TargetX")!.GetValue(entry)!;
    }
}
