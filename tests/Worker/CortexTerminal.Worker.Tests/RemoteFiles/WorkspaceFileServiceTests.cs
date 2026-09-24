using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Worker.RemoteFiles;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace CortexTerminal.Worker.Tests.RemoteFiles;

public sealed class WorkspaceFileServiceTests
{
    private static WorkspaceFileService NewService()
        => new(maxListEntries: 100, NullLogger<WorkspaceFileService>.Instance);

    [Fact]
    public void CreateWorkspaceDirectory_RelativePath_ResolvesUnderHome()
    {
        var ack = NewService().CreateWorkspaceDirectory(
            new CreateWorkspaceDirectoryCommand("ws-1", "CortermWorkspace/proj"));

        ack.Success.Should().BeTrue();
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        ack.ResolvedPath.Should().StartWith(home);
        Directory.Exists(ack.ResolvedPath).Should().BeTrue();
    }

    [Fact]
    public void CreateWorkspaceDirectory_AbsoluteInsideHome_IsAccepted()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var target = Path.Combine(home, "CortermWorkspace-abs-test");

        var ack = NewService().CreateWorkspaceDirectory(
            new CreateWorkspaceDirectoryCommand("ws-1", target));

        ack.Success.Should().BeTrue();
        ack.ResolvedPath.Should().Be(Path.GetFullPath(target));
    }

    [Fact]
    public void CreateWorkspaceDirectory_OutsideHome_IsAllowed_Relaxed()
    {
        // 设计决策：根不再限制在 home 内（安全边界是工作区根本身）；
        // 外部盘/挂载点上的项目目录是合法工作区。
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var outside = Path.Combine(Path.GetDirectoryName(home)!, "corterm-outside-test");

        var ack = NewService().CreateWorkspaceDirectory(
            new CreateWorkspaceDirectoryCommand("ws-1", outside));
        ack.Success.Should().BeTrue();

        // 相对路径（../elsewhere）相对 home 解析；新策略下不再被拒——
        // 根本身就是沙箱边界，解析成什么路径就在什么路径内。
        var traversal = NewService().CreateWorkspaceDirectory(
            new CreateWorkspaceDirectoryCommand("ws-2", "../elsewhere"));
        traversal.Success.Should().BeTrue();
    }

    [Fact]
    public void CreateWorkspaceDirectory_EmptyPath_IsRejected()
    {
        var ack = NewService().CreateWorkspaceDirectory(
            new CreateWorkspaceDirectoryCommand("ws-1", " "));
        ack.Success.Should().BeFalse();
        ack.Error!.Code.Should().Be(FileTransferErrorCode.PathInvalid);
    }
}
