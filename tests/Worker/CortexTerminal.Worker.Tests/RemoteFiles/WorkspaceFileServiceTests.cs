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
        // 相对路径相对 home 解析（../elsewhere 也允许——根本身即沙箱边界，
        // 「根可在 home 外」的策略断言在 TildeRootTests.OutsideHome_IsAllowed_Relaxed，
        // 不落盘；这里只验证 home 内可写的相对路径创建成功）。
        var rel = $"corterm-rel-{Guid.NewGuid():N}";
        var ack = NewService().CreateWorkspaceDirectory(
            new CreateWorkspaceDirectoryCommand("ws-rel", rel));
        ack.Success.Should().BeTrue();
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
