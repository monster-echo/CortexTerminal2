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
    public void CreateWorkspaceDirectory_EscapingHome_IsRejected()
    {
        // GetTempPath 在 Windows 上位于 home 内，不能当“外部目录”用；
        // 用 home 的同级目录，三平台语义一致。
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var outside = Path.Combine(Path.GetDirectoryName(home)!, "corterm-outside-test");

        var ack = NewService().CreateWorkspaceDirectory(
            new CreateWorkspaceDirectoryCommand("ws-1", outside));
        ack.Success.Should().BeFalse();
        ack.Error!.Code.Should().Be(FileTransferErrorCode.AccessDenied);

        // 词法逃逸同样拒绝
        var traversal = NewService().CreateWorkspaceDirectory(
            new CreateWorkspaceDirectoryCommand("ws-2", "../elsewhere"));
        traversal.Success.Should().BeFalse();
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
