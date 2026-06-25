using CortexTerminal.Gateway.Sessions;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Sessions;

public sealed class ArtifactFilenameValidatorTests
{
    [Theory]
    [InlineData("a.txt")]
    [InlineData("A-B_1.7z")]
    [InlineData("123")]
    [InlineData("a")]
    [InlineData("1.png")]
    [InlineData("archive.tar.gz")]
    [InlineData("underscore_name.log")]
    [InlineData("dash-name.log")]
    [InlineData("UPPER.PNG")]
    [InlineData("MixEd.Cs")]
    public void IsValid_AcceptsSafeNames(string filename)
    {
        ArtifactFilenameValidator.IsValid(filename).Should().BeTrue();
    }

    [Theory]
    [InlineData("../etc/passwd")]
    [InlineData("..\\secret")]
    [InlineData(".hidden")]
    [InlineData("-leading-dash")]
    [InlineData("")]
    [InlineData("foo/bar")]
    [InlineData("foo:bar")]
    [InlineData("foo bar")]
    [InlineData("foo\nbar")]
    [InlineData("中文.txt")]
    public void IsValid_RejectsUnsafeNames(string filename)
    {
        ArtifactFilenameValidator.IsValid(filename).Should().BeFalse();
    }

    [Fact]
    public void IsValid_RejectsTooLongName()
    {
        var tooLong = new string('a', 256);
        ArtifactFilenameValidator.IsValid(tooLong).Should().BeFalse();
    }

    [Fact]
    public void IsValid_AcceptsMaxLengthName()
    {
        var max = new string('a', 255);
        ArtifactFilenameValidator.IsValid(max).Should().BeTrue();
    }
}
