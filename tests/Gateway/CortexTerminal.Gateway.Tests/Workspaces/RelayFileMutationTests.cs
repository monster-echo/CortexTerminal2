using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Tests.Hubs;
using CortexTerminal.Gateway.Workers;
using CortexTerminal.Gateway.Workspaces;
using FluentAssertions;
using Microsoft.Extensions.Options;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Workspaces;

/// <summary>Mkdir / WriteText / Rename / Delete 的 Gateway 编排：path 校验、RPC 传参、错误码透传。</summary>
public sealed class RelayFileMutationTests
{
    private static (RelayFileTransferService Service, RecordingMutationDispatcher Dispatcher, WorkspaceRegistry Workspaces) NewService()
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-1", "conn-1", ownerUserId: "test-user");
        var workspaces = TestSessionFactory.CreateWorkspaceRegistry();
        var dispatcher = new RecordingMutationDispatcher();
        var service = new RelayFileTransferService(
            workers,
            dispatcher,
            workspaces,
            Options.Create(new RelayOptions
            {
                SharedSecret = "test-secret",
                PublicUrl = "https://relay.corterm.test",
            }));
        return (service, dispatcher, workspaces);
    }

    [Fact]
    public async Task Mkdir_PassesWorkspaceRootAndPath()
    {
        var (service, dispatcher, workspaces) = NewService();
        var ws = await workspaces.CreateAsync("test-user", "worker-1", "proj", "/home/user/proj");

        await service.MkdirAsync("test-user", ws.Id, "docs", CancellationToken.None);

        dispatcher.LastCall.Should().Be(("Mkdir", "/home/user/proj", "docs"));
    }

    [Fact]
    public async Task WriteText_PassesContent()
    {
        var (service, dispatcher, workspaces) = NewService();
        var ws = await workspaces.CreateAsync("test-user", "worker-1", "proj", "/home/user/proj");

        await service.WriteTextAsync("test-user", ws.Id, "a.txt", "hello", CancellationToken.None);

        dispatcher.LastCall.Should().Be(("WriteTextFile", "/home/user/proj", "a.txt"));
        dispatcher.LastContent.Should().Be("hello");
    }

    [Fact]
    public async Task Rename_PassesNewName()
    {
        var (service, dispatcher, workspaces) = NewService();
        var ws = await workspaces.CreateAsync("test-user", "worker-1", "proj", "/home/user/proj");

        await service.RenameAsync("test-user", ws.Id, "a.txt", "b.txt", CancellationToken.None);

        dispatcher.LastCall.Should().Be(("Rename", "/home/user/proj", "a.txt"));
        dispatcher.LastNewName.Should().Be("b.txt");
    }

    [Fact]
    public async Task EmptyPath_ThrowsPathInvalid()
    {
        var (service, _, workspaces) = NewService();
        var ws = await workspaces.CreateAsync("test-user", "worker-1", "proj", "/home/user/proj");

        var ex = await Assert.ThrowsAsync<WorkspaceFileServiceException>(
            () => service.MkdirAsync("test-user", ws.Id, " ", CancellationToken.None));
        ex.Code.Should().Be(FileTransferErrorCode.PathInvalid);

        await Assert.ThrowsAsync<WorkspaceFileServiceException>(
            () => service.DeleteAsync("test-user", ws.Id, "", CancellationToken.None));
    }

    [Fact]
    public async Task EmptyNewName_ThrowsPathInvalid()
    {
        var (service, _, workspaces) = NewService();
        var ws = await workspaces.CreateAsync("test-user", "worker-1", "proj", "/home/user/proj");

        var ex = await Assert.ThrowsAsync<WorkspaceFileServiceException>(
            () => service.RenameAsync("test-user", ws.Id, "a.txt", "", CancellationToken.None));
        ex.Code.Should().Be(FileTransferErrorCode.PathInvalid);
    }

    [Fact]
    public async Task WorkerError_IsRethrownAsServiceException()
    {
        var (service, dispatcher, workspaces) = NewService();
        var ws = await workspaces.CreateAsync("test-user", "worker-1", "proj", "/home/user/proj");
        dispatcher.NextResult = new FileOpResult(
            new FileOperationError(FileTransferErrorCode.PathNotFound, "no such file"));

        var ex = await Assert.ThrowsAsync<WorkspaceFileServiceException>(
            () => service.DeleteAsync("test-user", ws.Id, "ghost.txt", CancellationToken.None));
        ex.Code.Should().Be(FileTransferErrorCode.PathNotFound);
        ex.Message.Should().Be("no such file");
    }

    private sealed class RecordingMutationDispatcher : NoOpWorkerCommandDispatcher
    {
        public (string Method, string RootPath, string Path) LastCall = ("", "", "");
        public string? LastContent;
        public string? LastNewName;
        public FileOpResult NextResult = new(null);

        public override Task<FileOpResult> MkdirAsync(string workerConnectionId, string rootDir, string relativePath, CancellationToken cancellationToken)
        {
            LastCall = ("Mkdir", rootDir, relativePath);
            return Task.FromResult(NextResult);
        }

        public override Task<FileOpResult> WriteTextFileAsync(string workerConnectionId, string rootDir, string relativePath, string content, CancellationToken cancellationToken)
        {
            LastCall = ("WriteTextFile", rootDir, relativePath);
            LastContent = content;
            return Task.FromResult(NextResult);
        }

        public override Task<FileOpResult> RenameAsync(string workerConnectionId, string rootDir, string relativePath, string newName, CancellationToken cancellationToken)
        {
            LastCall = ("Rename", rootDir, relativePath);
            LastNewName = newName;
            return Task.FromResult(NextResult);
        }

        public override Task<FileOpResult> DeleteAsync(string workerConnectionId, string rootDir, string relativePath, CancellationToken cancellationToken)
        {
            LastCall = ("Delete", rootDir, relativePath);
            return Task.FromResult(NextResult);
        }
    }}
