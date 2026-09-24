using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Worker.RemoteFiles;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Worker.Tests.RemoteFiles;

public class TildeRootTests
{
    [Fact]
    public void Tilde_ResolvesToHome()
    {
        var ok = WorkspaceFileService.TryResolveWorkspaceDir("~", out var path, out var error);
        ok.Should().BeTrue();
        error.Should().BeNull();
        path.Should().Be(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
    }

    [Fact]
    public void TildeSubPath_ResolvesUnderHome()
    {
        var ok = WorkspaceFileService.TryResolveWorkspaceDir("~/Projects/demo", out var path, out var error);
        ok.Should().BeTrue();
        error.Should().BeNull();
        path.Should().Contain("Projects/demo");
    }

    [Fact]
    public void OutsideHome_StillRejected()
    {
        var ok = WorkspaceFileService.TryResolveWorkspaceDir("/tmp/outside", out _, out var error);
        ok.Should().BeFalse();
        error!.Code.Should().Be(FileTransferErrorCode.AccessDenied);
    }
}
