using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Worker.RemoteFiles;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Worker.Tests.RemoteFiles;

/// <summary>
/// 工作区根解析策略（design 评审后）：
/// - 根可以是任意绝对路径（不再限制 home 内）；"~" 展开为 home；
/// - 候选路径若为符号链接，解析为最终目标作为根；
/// - 安全边界是「工作区根本身」，由 RemotePathValidator 在每次请求时守卫。
/// 断言全部用 Path API 组装，linux/osx/windows 矩阵下等价。
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
    public void OutsideHome_IsAllowed_Relaxed()
    {
        // 设计决策：根不再限制在 home 内（项目可在任意挂载点/外部盘）。
        // 不真正创建目录——解析阶段不需要路径存在。
        var outside = Path.GetFullPath(Path.Combine(
            Path.GetDirectoryName(Home)!, "corterm-anywhere"));
        var ok = WorkspaceFileService.TryResolveWorkspaceDir(outside, out var path, out var error);
        ok.Should().BeTrue();
        error.Should().BeNull();
        Path.GetFullPath(path).Should().Be(outside);
    }

    [Fact]
    public void SymlinkRoot_ResolvesToFinalTarget()
    {
        if (OperatingSystem.IsWindows()) return; // symlink 需特权
        var realDir = Path.Combine(Home, "corterm-real-target");
        Directory.CreateDirectory(realDir);
        var link = Path.Combine(Home, $"corterm-link-{Guid.NewGuid():N}");
        Directory.CreateSymbolicLink(link, realDir);

        try
        {
            var ok = WorkspaceFileService.TryResolveWorkspaceDir(link, out var path, out var error);
            ok.Should().BeTrue();
            error.Should().BeNull();
            Path.GetFullPath(path).Should().Be(Path.GetFullPath(realDir));
        }
        finally
        {
            File.Delete(link);
        }
    }
}
