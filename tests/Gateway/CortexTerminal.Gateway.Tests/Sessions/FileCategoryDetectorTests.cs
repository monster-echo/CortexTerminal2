using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Sessions;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Sessions;

public sealed class FileCategoryDetectorTests
{
    [Theory]
    [InlineData("photo.png", ArtifactFileCategory.Image)]
    [InlineData("photo.jpg", ArtifactFileCategory.Image)]
    [InlineData("photo.JPEG", ArtifactFileCategory.Image)]
    [InlineData("anim.gif", ArtifactFileCategory.Image)]
    [InlineData("doc.pdf", ArtifactFileCategory.Pdf)]
    [InlineData("clip.mp4", ArtifactFileCategory.Video)]
    [InlineData("clip.mov", ArtifactFileCategory.Video)]
    [InlineData("tune.mp3", ArtifactFileCategory.Audio)]
    [InlineData("tune.wav", ArtifactFileCategory.Audio)]
    [InlineData("bundle.zip", ArtifactFileCategory.Archive)]
    [InlineData("bundle.tar.gz", ArtifactFileCategory.Archive)]
    [InlineData("bundle.7z", ArtifactFileCategory.Archive)]
    [InlineData("Program.cs", ArtifactFileCategory.Code)]
    [InlineData("app.tsx", ArtifactFileCategory.Code)]
    [InlineData("main.py", ArtifactFileCategory.Code)]
    [InlineData("deploy.sh", ArtifactFileCategory.Code)]
    [InlineData("config.json", ArtifactFileCategory.Code)]
    [InlineData("config.yaml", ArtifactFileCategory.Code)]
    [InlineData("notes.txt", ArtifactFileCategory.Text)]
    [InlineData("README.md", ArtifactFileCategory.Text)]
    [InlineData("data.csv", ArtifactFileCategory.Text)]
    public void Detect_ReturnsExpectedCategory(string filename, string expected)
    {
        FileCategoryDetector.Detect(filename).Should().Be(expected);
    }

    [Theory]
    [InlineData("README")]
    [InlineData("noext")]
    [InlineData("weird.xyz")]
    [InlineData("weird.")]
    public void Detect_UnknownOrNoExtension_ReturnsUnknown(string filename)
    {
        FileCategoryDetector.Detect(filename).Should().Be(ArtifactFileCategory.Unknown);
    }

    [Fact]
    public void Detect_DoubleExtension_ResolvesByLast()
    {
        FileCategoryDetector.Detect("archive.tar.gz").Should().Be(ArtifactFileCategory.Archive);
        FileCategoryDetector.Detect("image.tar.gz.png").Should().Be(ArtifactFileCategory.Image);
    }
}
