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
    [InlineData("-leading-dash")]
    [InlineData("foo bar")]
    [InlineData("中文.txt")]
    [InlineData("屏幕截图 2026-06-28.png")]
    [InlineData("Screenshot (1).png")]
    [InlineData("data + v2.log")]
    [InlineData("file,with,commas.csv")]
    [InlineData("name;semi.txt")]
    [InlineData("hydrogen-H₂O.png")]
    public void IsValid_AcceptsSafeNames(string filename)
    {
        ArtifactFilenameValidator.IsValid(filename).Should().BeTrue();
    }

    [Theory]
    [InlineData("../etc/passwd")]
    [InlineData("..\\secret")]
    [InlineData(".hidden")]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("foo/bar")]
    [InlineData("foo\\bar")]
    [InlineData("foo:bar")]
    [InlineData("foo\nbar")]
    [InlineData("foo<bar")]
    [InlineData("foo>bar")]
    [InlineData("foo|bar")]
    [InlineData("foo?bar")]
    [InlineData("foo*bar")]
    [InlineData("foo\"bar")]
    [InlineData("CON")]
    [InlineData("PRN.txt")]
    [InlineData("NUL.log")]
    [InlineData("COM1")]
    [InlineData("LPT9.dat")]
    [InlineData("trailing.")]
    [InlineData("trailing ")]
    [InlineData("..traversal")]
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
