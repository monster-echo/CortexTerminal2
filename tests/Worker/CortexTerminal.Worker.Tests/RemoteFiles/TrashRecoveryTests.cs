using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Worker.RemoteFiles;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace CortexTerminal.Worker.Tests.RemoteFiles;
public sealed class TrashRecoveryTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "corterm-trash-test-" + Guid.NewGuid().ToString("N"));
    private readonly WorkspaceFileService _service = new(100, NullLogger<WorkspaceFileService>.Instance);
    public TrashRecoveryTests() => Directory.CreateDirectory(_root);
    public void Dispose() => Directory.Delete(_root, true);
    [Fact]
    public void File_IsRetainedAndCanBeRestoredWithoutChangingItsBytes()
    {
        File.WriteAllText(Path.Combine(_root, "notes.txt"), "你好 corterm");
        var id = Guid.NewGuid().ToString("N");
        _service.Trash(_root, "notes.txt", id).Error.Should().BeNull();
        File.Exists(Path.Combine(_root, "notes.txt")).Should().BeFalse();
        File.ReadAllText(Path.Combine(_root, ".corterm-trash", id, "payload")).Should().Be("你好 corterm");
        _service.Trash(_root, "notes.txt", id).Error.Should().BeNull(); // Retry is idempotent before restore.
        _service.RestoreTrash(_root, id).Error.Should().BeNull();
        File.ReadAllText(Path.Combine(_root, "notes.txt")).Should().Be("你好 corterm");
        _service.Trash(_root, "notes.txt", id).Error.Should().NotBeNull(); // Cannot re-delete with an old receipt.
    }
    [Fact]
    public void DirectoryAndChildren_AreMovedAndRestoredTogether()
    {
        Directory.CreateDirectory(Path.Combine(_root, "project"));
        File.WriteAllText(Path.Combine(_root, "project", "readme.md"), "data");
        var id = Guid.NewGuid().ToString("N");
        _service.Trash(_root, "project", id).Error.Should().BeNull();
        _service.RestoreTrash(_root, id).Error.Should().BeNull();
        File.ReadAllText(Path.Combine(_root, "project", "readme.md")).Should().Be("data");
    }
    [Fact]
    public void Restore_RefusesToOverwriteANewerFile()
    {
        var path = Path.Combine(_root, "file"); File.WriteAllText(path, "old");
        var id = Guid.NewGuid().ToString("N");
        _service.Trash(_root, "file", id).Error.Should().BeNull(); File.WriteAllText(path, "new");
        _service.RestoreTrash(_root, id).Error!.Code.Should().Be(FileTransferErrorCode.PathInvalid);
        File.ReadAllText(path).Should().Be("new");
        File.ReadAllText(Path.Combine(_root, ".corterm-trash", id, "payload")).Should().Be("old");
    }
    [Fact]
    public void InvalidReceiptRootAndTraversal_AreRejected()
    {
        var id = Guid.NewGuid().ToString("N");
        _service.Trash(_root, ".", id).Error.Should().NotBeNull();
        _service.Trash(_root, "../outside", id).Error.Should().NotBeNull();
        _service.RestoreTrash(_root, "../outside").Error.Should().NotBeNull();
        _service.Trash(_root, ".corterm-trash", id).Error.Should().NotBeNull();
    }
    [Fact]
    public void AnExistingUnmanagedFolder_IsNotAdoptedOrOverwritten()
    {
        Directory.CreateDirectory(Path.Combine(_root, ".corterm-trash"));
        File.WriteAllText(Path.Combine(_root, "file"), "keep");
        _service.Trash(_root, "file", Guid.NewGuid().ToString("N")).Error!.Code.Should().Be(FileTransferErrorCode.AccessDenied);
        File.ReadAllText(Path.Combine(_root, "file")).Should().Be("keep");
    }
}
