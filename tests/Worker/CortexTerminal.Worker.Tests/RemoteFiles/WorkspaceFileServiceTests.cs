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
    public void CreateWorkspaceDirectory_RelativePath_ResolvesAgainstHome()
    {
        // 相对路径（../elsewhere）相对 home 解析；新策略（根不限 home）下不再被拒——
        // 根本身就是沙箱边界，解析成什么路径就在什么路径内。
        // 「根可在 home 外」这一策略点由 TildeRootTests.OutsideHome_IsAllowed_Relaxed 覆盖
        // （不落盘，三平台等价；home 外目录在 CI 上通常不可写）。
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
