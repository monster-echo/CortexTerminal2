using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Worker.RemoteFiles;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Worker.Tests.RemoteFiles;

public sealed class RemoteDirectoryListerTests : IDisposable
{
    private readonly string _root = Directory.CreateDirectory(
        Path.Combine(Path.GetTempPath(), $"corterm-ls-{Guid.NewGuid():N}")).FullName;
    private readonly RemoteDirectoryLister _lister;

    public RemoteDirectoryListerTests()
    {
        _lister = new RemoteDirectoryLister(_root, maxEntries: 100);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* temp cleanup */ }
    }

    [Fact]
    public void ListsDirectoriesFirst_ThenFiles_WithDotfilesIncluded()
    {
        File.WriteAllText(Path.Combine(_root, "zeta.txt"), "hello");
        File.WriteAllText(Path.Combine(_root, ".hidden"), "x");
        File.WriteAllText(Path.Combine(_root, "中文.txt"), "y");
        Directory.CreateDirectory(Path.Combine(_root, "sub"));

        var result = _lister.List("");

        result.Error.Should().BeNull();
        result.Listing.Should().NotBeNull();
        var names = result.Listing!.Entries.Select(e => e.Name).ToArray();
        names.Should().Equal("sub", ".hidden", "zeta.txt", "中文.txt");
        result.Listing!.Entries[0].IsDirectory.Should().BeTrue();
        result.Listing!.Entries[1].SizeBytes.Should().Be(1);
        result.Listing!.Truncated.Should().BeFalse();
    }

    [Fact]
    public void EmptyDirectory_ReturnsEmptyEntries()
    {
        var result = _lister.List("");

        result.Listing!.Entries.Should().BeEmpty();
    }

    [Fact]
    public void MissingPath_ReturnsPathNotFound()
    {
        var result = _lister.List("no-such-dir");

        result.Listing.Should().BeNull();
        result.Error!.Code.Should().Be(FileTransferErrorCode.PathNotFound);
    }

    [Fact]
    public void FilePath_ReturnsNotADirectory()
    {
        File.WriteAllText(Path.Combine(_root, "file.txt"), "x");

        var result = _lister.List("file.txt");

        result.Error!.Code.Should().Be(FileTransferErrorCode.NotADirectory);
    }

    [Fact]
    public void EntriesBeyondCap_SetTruncatedFlag()
    {
        for (var i = 0; i < 5; i++)
        {
            File.WriteAllText(Path.Combine(_root, $"f{i}.txt"), "x");
        }
        var smallLister = new RemoteDirectoryLister(_root, maxEntries: 3);

        var result = smallLister.List("");

        result.Listing!.Entries.Should().HaveCount(3);
        result.Listing!.Truncated.Should().BeTrue();
    }

    [Fact]
    public void PathEscape_IsRejectedAsInvalid()
    {
        var result = _lister.List("../outside");

        result.Error!.Code.Should().Be(FileTransferErrorCode.PathInvalid);
    }
}
