using CortexTerminal.Contracts.Sessions;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.RemoteFiles;

/// <summary>
/// Rules migrated from the retired ArtifactFilenameValidator tests, adapted to per-segment
/// validation (leading dots are now legal — dotfiles are first-class entries).
/// </summary>
public sealed class RemoteFileNameValidatorTests
{
    [Theory]
    [InlineData("note.txt")]
    [InlineData("屏幕截图 2026.png")]
    [InlineData("Screenshot (1).png")]
    [InlineData(".ssh")]
    [InlineData(".config")]
    public void Accepts_RealWorldSegments(string segment)
    {
        RemoteFileNameValidator.IsValid(segment).Should().BeTrue();
    }

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("a/b")]
    [InlineData("a\\b")]
    [InlineData("a:b")]
    [InlineData("a<b>c")]
    [InlineData("a|b")]
    [InlineData("what?")]
    [InlineData("a*b")]
    [InlineData("say \"hi\"")]
    [InlineData("..")]
    [InlineData("file.")]
    [InlineData("CON")]
    [InlineData("aux")]
    [InlineData("com1.txt")]
    [InlineData("lpt9")]
    public void Rejects_HostileSegments(string segment)
    {
        RemoteFileNameValidator.IsValid(segment).Should().BeFalse($"{segment}");
    }

    [Fact]
    public void Accepts_InteriorSpaces()
    {
        RemoteFileNameValidator.IsValid("屏幕截图 2026").Should().BeTrue();
    }

    [Fact]
    public void Rejects_OversizedSegment_WithReason()
    {
        var ok = RemoteFileNameValidator.TryValidateSegment(new string('a', 256), out var reason);

        ok.Should().BeFalse();
        reason.Should().Contain("255");
    }
}
