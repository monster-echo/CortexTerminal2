using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Worker.RemoteFiles;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace CortexTerminal.Worker.Tests.RemoteFiles;

/// <summary>Mkdir / WriteTextFile / Rename / Delete 的 Worker 端行为与路径安全校验。</summary>
public sealed class RemoteFileMutationTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"corterm-mut-{Guid.NewGuid():N}");

    private WorkspaceFileService NewService()
        => new(maxListEntries: 100, NullLogger<WorkspaceFileService>.Instance);

    private string Root
    {
        get
        {
            Directory.CreateDirectory(_root);
            return _root;
        }
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* temp cleanup */ }
    }

    // ---- Mkdir ----

    [Fact]
    public void Mkdir_CreatesSingleLevel_WhenParentExists()
    {
        var result = NewService().Mkdir(Root, "docs");

        result.Error.Should().BeNull();
        Directory.Exists(Path.Combine(Root, "docs")).Should().BeTrue();
    }

    [Fact]
    public void Mkdir_MissingParent_IsRejected()
    {
        var result = NewService().Mkdir(Root, "a/b");

        result.Error!.Code.Should().Be(FileTransferErrorCode.PathInvalid);
        Directory.Exists(Path.Combine(Root, "a")).Should().BeFalse();
    }

    [Fact]
    public void Mkdir_AlreadyExists_IsRejected()
    {
        Directory.CreateDirectory(Path.Combine(Root, "docs"));

        var result = NewService().Mkdir(Root, "docs");

        result.Error!.Code.Should().Be(FileTransferErrorCode.PathInvalid);
    }

    // ---- WriteTextFile ----

    [Fact]
    public void WriteTextFile_CreatesUtf8Content()
    {
        var result = NewService().WriteTextFile(Root, "hello.txt", "你好 world");

        result.Error.Should().BeNull();
        File.ReadAllText(Path.Combine(Root, "hello.txt")).Should().Be("你好 world");
    }

    [Fact]
    public void WriteTextFile_OverwritesExisting()
    {
        File.WriteAllText(Path.Combine(Root, "a.txt"), "old");

        var result = NewService().WriteTextFile(Root, "a.txt", "new");

        result.Error.Should().BeNull();
        File.ReadAllText(Path.Combine(Root, "a.txt")).Should().Be("new");
    }

    [Fact]
    public void WriteTextFile_MissingParent_IsRejected()
    {
        var result = NewService().WriteTextFile(Root, "nope/a.txt", "x");

        result.Error!.Code.Should().Be(FileTransferErrorCode.PathNotFound);
    }

    // ---- Rename ----

    [Fact]
    public void Rename_File_Works()
    {
        File.WriteAllText(Path.Combine(Root, "a.txt"), "x");

        var result = NewService().Rename(Root, "a.txt", "b.txt");

        result.Error.Should().BeNull();
        File.Exists(Path.Combine(Root, "b.txt")).Should().BeTrue();
        File.Exists(Path.Combine(Root, "a.txt")).Should().BeFalse();
    }

    [Fact]
    public void Rename_Directory_Works()
    {
        Directory.CreateDirectory(Path.Combine(Root, "old"));

        var result = NewService().Rename(Root, "old", "new");

        result.Error.Should().BeNull();
        Directory.Exists(Path.Combine(Root, "new")).Should().BeTrue();
    }

    [Fact]
    public void Rename_InvalidNewName_IsRejected()
    {
        File.WriteAllText(Path.Combine(Root, "a.txt"), "x");

        var result = NewService().Rename(Root, "a.txt", "../evil");

        result.Error!.Code.Should().Be(FileTransferErrorCode.PathInvalid);
        File.Exists(Path.Combine(Root, "a.txt")).Should().BeTrue();
    }

    [Fact]
    public void Rename_TargetExists_IsRejected()
    {
        File.WriteAllText(Path.Combine(Root, "a.txt"), "x");
        File.WriteAllText(Path.Combine(Root, "b.txt"), "y");

        var result = NewService().Rename(Root, "a.txt", "b.txt");

        result.Error!.Code.Should().Be(FileTransferErrorCode.PathInvalid);
    }

    [Fact]
    public void Rename_MissingSource_IsRejected()
    {
        var result = NewService().Rename(Root, "ghost.txt", "live.txt");

        result.Error!.Code.Should().Be(FileTransferErrorCode.FileNotFound);
    }

    // ---- Delete ----

    [Fact]
    public void Delete_File_RemovesIt()
    {
        File.WriteAllText(Path.Combine(Root, "a.txt"), "x");

        var result = NewService().Delete(Root, "a.txt");

        result.Error.Should().BeNull();
        File.Exists(Path.Combine(Root, "a.txt")).Should().BeFalse();
    }

    [Fact]
    public void Delete_Directory_RemovesRecursively()
    {
        Directory.CreateDirectory(Path.Combine(Root, "dir", "nested"));
        File.WriteAllText(Path.Combine(Root, "dir", "nested", "a.txt"), "x");

        var result = NewService().Delete(Root, "dir");

        result.Error.Should().BeNull();
        Directory.Exists(Path.Combine(Root, "dir")).Should().BeFalse();
    }

    [Fact]
    public void Delete_WorkspaceRoot_IsRejected()
    {
        var result = NewService().Delete(Root, "");

        result.Error!.Code.Should().Be(FileTransferErrorCode.PathInvalid);
        Directory.Exists(_root).Should().BeTrue();
    }

    [Fact]
    public void Delete_MissingPath_IsRejected()
    {
        var result = NewService().Delete(Root, "ghost.txt");

        result.Error!.Code.Should().Be(FileTransferErrorCode.FileNotFound);
    }

    [Fact]
    public void Delete_TraversalPath_IsRejected()
    {
        var result = NewService().Delete(Root, "../outside");

        result.Error!.Code.Should().Be(FileTransferErrorCode.PathInvalid);
    }
}
