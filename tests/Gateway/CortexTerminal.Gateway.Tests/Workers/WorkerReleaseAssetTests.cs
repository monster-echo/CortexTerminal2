using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Workers;

public sealed class WorkerReleaseAssetTests
{
    [Theory]
    [InlineData("Darwin 24.0.0", "Arm64", "corterm-osx-arm64.tar.gz")]
    [InlineData("Windows 11", "X64", "corterm-win-x64.zip")]
    [InlineData("Linux", "Arm64", "corterm-linux-arm64.tar.gz")]
    [InlineData(null, null, "corterm-linux-x64.tar.gz")]
    public void GetAssetName_ReturnsReleaseArtifactName(string? operatingSystem, string? architecture, string expected)
    {
        WorkerReleaseAsset.GetAssetName(operatingSystem, architecture).Should().Be(expected);
    }
}
