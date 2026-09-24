using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Worker.RemoteFiles;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Worker.Tests.RemoteFiles;

/// <summary>
/// "~" 根展开（design/02 §4：新建首个工作区前的文件夹浏览起点）。
/// 断言全部用 Path API 组装，保证在 linux/osx/windows 测试矩阵下等价。
/// </summary>
public class TildeRootTests
{
    private static string Home =>
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    [Fact]
    public void Tilde_ResolvesToHome()
    {
        var ok = WorkspaceFileService.TryResolveWorkspaceDir("~", out var path, out var error);
        ok.Should().BeTrue();
        error.Should().BeNull();
        Path.GetFullPath(path).Should().Be(Path.GetFullPath(Home));
    }

    [Fact]
    public void TildeSubPath_ResolvesUnderHome()
    {
        var expected = Path.GetFullPath(Path.Combine(Home, "Projects", "demo"));
        var ok = WorkspaceFileService.TryResolveWorkspaceDir("~/Projects/demo", out var path, out var error);
        ok.Should().BeTrue();
        error.Should().BeNull();
        Path.GetFullPath(path).Should().Be(expected);
    }

    [Fact]
    public void OutsideHome_StillRejected()
    {
        var outside = Path.GetTempPath();
        var ok = WorkspaceFileService.TryResolveWorkspaceDir(outside, out _, out var error);
        ok.Should().BeFalse();
        error!.Code.Should().Be(FileTransferErrorCode.AccessDenied);
    }

    [Fact]
    public void LexicalDotDot_UnderHome_StillRejected()
    {
        var ok = WorkspaceFileService.TryResolveWorkspaceDir("~/../escape", out _, out var error);
        ok.Should().BeFalse();
        error.Should().NotBeNull();
    }
}
