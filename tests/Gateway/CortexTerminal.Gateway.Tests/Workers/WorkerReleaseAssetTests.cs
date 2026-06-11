using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Workers;

public sealed class WorkerReleaseAssetTests
{
    [Theory]
    [InlineData("Darwin 24.0.0", "Arm64", "corterm-osx-arm64.tar.gz")]
    [InlineData("macOS 26.2.0", "Arm64", "corterm-osx-arm64.tar.gz")]
    [InlineData("Windows 11", "X64", "corterm-win-x64.zip")]
    [InlineData("Linux", "Arm64", "corterm-linux-arm64.tar.gz")]
    [InlineData("Ubuntu 24.04.3 LTS", "X64", "corterm-linux-x64.tar.gz")]
    public void GetAssetName_ReturnsReleaseArtifactName(string? operatingSystem, string? architecture, string expected)
    {
        WorkerReleaseAsset.GetAssetName(operatingSystem, architecture).Should().Be(expected);
    }

    [Fact]
    public void GetAssetName_Throws_WhenOperatingSystemIsNull()
    {
        var act = () => WorkerReleaseAsset.GetAssetName(null, "Arm64");
        act.Should().Throw<InvalidOperationException>();
    }

    [Theory]
    [InlineData("FreeBSD 14.0")]
    [InlineData("UnknownOS")]
    [InlineData("HarmonyOS 5.0")]
    public void GetAssetName_Throws_ForUnsupportedOS(string operatingSystem)
    {
        var act = () => WorkerReleaseAsset.GetAssetName(operatingSystem, "Arm64");
        act.Should().Throw<InvalidOperationException>().Which.Message.Should().Contain(operatingSystem);
    }
}
