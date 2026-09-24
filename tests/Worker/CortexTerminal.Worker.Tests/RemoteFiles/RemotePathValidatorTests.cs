using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Worker.RemoteFiles;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Worker.Tests.RemoteFiles;

public sealed class RemotePathValidatorTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"corterm-pv-{Guid.NewGuid():N}");

    private void CreateRoot()
    {
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* temp cleanup */ }
    }

    private void Resolve(string? relativePath, out bool ok, out string fullPath, out string? errorCode)
    {
        ok = RemotePathValidator.TryResolve(_root, relativePath, out fullPath, out var error);
        errorCode = error?.Code;
    }

    [Fact]
    public void EmptyPath_ResolvesToRoot()
    {
        CreateRoot();
        foreach (var path in new[] { "", ".", null })
        {
            Resolve(path, out var ok, out var fullPath, out _);
            ok.Should().BeTrue();
            Path.GetFullPath(fullPath).Should().Be(Path.GetFullPath(_root));
        }
    }

    [Theory]
    [InlineData("docs")]
    [InlineData("docs/pics")]
    [InlineData(".ssh/config")]
    [InlineData("屏幕截图 2026.png")]
    [InlineData("Screenshot (1).png")]
    public void ValidRelativePaths_ResolveInsideRoot(string relativePath)
    {
        CreateRoot();
        Resolve(relativePath, out var ok, out var fullPath, out _);
        ok.Should().BeTrue($"{relativePath} should be accepted");
        fullPath.Should().StartWith(Path.GetFullPath(_root));
    }

    [Theory]
    [InlineData("..")]
    [InlineData("a/../b")]
    [InlineData("a/..")]
    [InlineData("/etc/passwd")]
    [InlineData("C:/Windows")]
    [InlineData("a//b")]
    [InlineData("a/./b")]
    [InlineData("file*")]
    [InlineData("a<b>")]
    [InlineData("file.")]
    [InlineData(" leadingSpace")]
    [InlineData("trailingSpace ")]
    [InlineData("CON")]
    [InlineData("com1")]
    public void HostilePaths_AreRejected(string relativePath)
    {
        CreateRoot();
        Resolve(relativePath, out var ok, out _, out var errorCode);
        ok.Should().BeFalse($"{relativePath} should be rejected");
        errorCode.Should().Be(FileTransferErrorCode.PathInvalid);
    }

    [Fact]
    public void OversizedSegment_IsRejected()
    {
        CreateRoot();
        var longName = new string('a', 256);
        Resolve(longName, out var ok, out _, out _);
        ok.Should().BeFalse();
    }

    [Fact]
    public void TooDeepPath_IsRejected()
    {
        CreateRoot();
        var deep = string.Join('/', Enumerable.Range(0, 33).Select(i => $"d{i}"));
        Resolve(deep, out var ok, out _, out _);
        ok.Should().BeFalse();
    }

    [Fact]
    public void OverlongPath_IsRejected()
    {
        CreateRoot();
        var longPath = string.Join('/', Enumerable.Range(0, 40).Select(_ => new string('a', 40)));
        Resolve(longPath, out var ok, out _, out _);
        ok.Should().BeFalse();
    }

    [Fact]
    public void SymlinkPointingOutsideRoot_IsFollowed()
    {
        if (OperatingSystem.IsWindows()) return; // symlink creation needs privileges on Windows
        CreateRoot();
        var outsideDir = Path.Combine(Path.GetTempPath(), $"corterm-pv-outside-{Guid.NewGuid():N}");
        Directory.CreateDirectory(outsideDir);
        try
        {
            var linkPath = Path.Combine(_root, "escape");
            Directory.CreateSymbolicLink(linkPath, outsideDir);

            Resolve("escape/file.txt", out var ok, out _, out var errorCode);
            ok.Should().BeTrue("product decision: symlinks are followed, not sandboxed");
            errorCode.Should().BeNull();
        }
        finally
        {
            Directory.Delete(outsideDir, recursive: true);
        }
    }

    [Fact]
    public void SymlinkPointingInsideRoot_IsAllowed()
    {
        if (OperatingSystem.IsWindows()) return;
        CreateRoot();
        var realDir = Path.Combine(_root, "real");
        Directory.CreateDirectory(realDir);
        Directory.CreateSymbolicLink(Path.Combine(_root, "alias"), realDir);

        Resolve("alias/file.txt", out var ok, out var fullPath, out _);
        ok.Should().BeTrue();
        fullPath.Should().StartWith(Path.GetFullPath(_root));
    }
}
