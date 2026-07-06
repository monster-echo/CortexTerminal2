using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Worker.Artifacts;
using FluentAssertions;

namespace CortexTerminal.Worker.Tests.Artifacts;

public sealed class FileCategoryDetectorTests
{
    [Theory]
    [InlineData("photo.png", ArtifactFileCategory.Image)]
    [InlineData("photo.jpg", ArtifactFileCategory.Image)]
    [InlineData("photo.JPEG", ArtifactFileCategory.Image)]
    [InlineData("anim.gif", ArtifactFileCategory.Image)]
    [InlineData("anim.webp", ArtifactFileCategory.Image)]
    [InlineData("paper.pdf", ArtifactFileCategory.Pdf)]
    [InlineData("clip.mp4", ArtifactFileCategory.Video)]
    [InlineData("clip.mov", ArtifactFileCategory.Video)]
    [InlineData("clip.mkv", ArtifactFileCategory.Video)]
    [InlineData("track.mp3", ArtifactFileCategory.Audio)]
    [InlineData("track.flac", ArtifactFileCategory.Audio)]
    [InlineData("bundle.zip", ArtifactFileCategory.Archive)]
    [InlineData("bundle.tar", ArtifactFileCategory.Archive)]
    [InlineData("bundle.tar.gz", ArtifactFileCategory.Archive)]
    [InlineData("bundle.7z", ArtifactFileCategory.Archive)]
    [InlineData("program.cs", ArtifactFileCategory.Code)]
    [InlineData("program.ts", ArtifactFileCategory.Code)]
    [InlineData("program.tsx", ArtifactFileCategory.Code)]
    [InlineData("script.py", ArtifactFileCategory.Code)]
    [InlineData("script.sh", ArtifactFileCategory.Code)]
    [InlineData("config.json", ArtifactFileCategory.Code)]
    [InlineData("config.yaml", ArtifactFileCategory.Code)]
    [InlineData("notes.txt", ArtifactFileCategory.Text)]
    [InlineData("README.md", ArtifactFileCategory.Text)]
    [InlineData("events.log", ArtifactFileCategory.Text)]
    public void Detect_MapsExtensionToCategory(string filename, string expected)
    {
        FileCategoryDetector.Detect(filename).Should().Be(expected);
    }

    [Theory]
    [InlineData("noextension")]
    [InlineData("README")]
    [InlineData("unknown.xyz")]
    [InlineData("archive.zzz")]
    public void Detect_UnknownOrNoExtension_ReturnsUnknown(string filename)
    {
        FileCategoryDetector.Detect(filename).Should().Be(ArtifactFileCategory.Unknown);
    }

    [Fact]
    public void Detect_CaseInsensitive_MapsPngToImage()
    {
        FileCategoryDetector.Detect("PHOTO.PNG").Should().Be(ArtifactFileCategory.Image);
    }
}
