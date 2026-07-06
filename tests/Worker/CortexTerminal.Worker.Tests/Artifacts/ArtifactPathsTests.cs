using CortexTerminal.Worker.Artifacts;
using FluentAssertions;

namespace CortexTerminal.Worker.Tests.Artifacts;

/// <summary>
/// ArtifactPaths is pure path arithmetic over the user profile dir. Tests verify the layout
/// (<c>~/.corterm/sessions/{sessionId}/artifacts/</c>) and idempotent directory creation.
/// We can't override <c>Environment.GetFolderPath</c> in tests, so we assert against
/// <see cref="Environment.SpecialFolder.UserProfile"/> at runtime.
/// </summary>
public sealed class ArtifactPathsTests
{
    [Fact]
    public void GetSessionArtifactsDir_CombinesProfileAndSessionAndArtifacts()
    {
        var expectedRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".corterm", "sessions");
        var dir = ArtifactPaths.GetSessionArtifactsDir("sess-1");
        dir.Should().Be(Path.Combine(expectedRoot, "sess-1", "artifacts"));
    }

    [Fact]
    public void GetSessionDir_CombinesProfileAndSession()
    {
        var expectedRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".corterm", "sessions");
        ArtifactPaths.GetSessionDir("sess-42").Should().Be(Path.Combine(expectedRoot, "sess-42"));
    }

    [Fact]
    public void EnsureSessionArtifactsDir_CreatesNestedDirectories()
    {
        // Sidestep the real profile: pick a sessionId that won't exist under the test profile.
        var sessionId = $"test-{Guid.NewGuid():N}";
        try
        {
            var dir = ArtifactPaths.GetSessionArtifactsDir(sessionId);
            Directory.Exists(dir).Should().BeFalse();

            ArtifactPaths.EnsureSessionArtifactsDir(sessionId);

            Directory.Exists(dir).Should().BeTrue();
        }
        finally
        {
            ArtifactPaths.DeleteSessionDir(sessionId);
        }
    }

    [Fact]
    public void EnsureSessionArtifactsDir_IsIdempotent()
    {
        var sessionId = $"test-{Guid.NewGuid():N}";
        try
        {
            var act = () => ArtifactPaths.EnsureSessionArtifactsDir(sessionId);
            act.Should().NotThrow();
            act.Should().NotThrow();
            Directory.Exists(ArtifactPaths.GetSessionArtifactsDir(sessionId)).Should().BeTrue();
        }
        finally
        {
            ArtifactPaths.DeleteSessionDir(sessionId);
        }
    }

    [Fact]
    public void DeleteSessionDir_RemovesAllContents()
    {
        var sessionId = $"test-{Guid.NewGuid():N}";
        var dir = ArtifactPaths.GetSessionArtifactsDir(sessionId);
        Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(dir, "leftover.txt"), "x");

        ArtifactPaths.DeleteSessionDir(sessionId);

        Directory.Exists(ArtifactPaths.GetSessionDir(sessionId)).Should().BeFalse();
    }

    [Fact]
    public void DeleteSessionDir_WhenMissing_IsNoOp()
    {
        var sessionId = $"never-existed-{Guid.NewGuid():N}";
        var act = () => ArtifactPaths.DeleteSessionDir(sessionId);
        act.Should().NotThrow();
    }
}
