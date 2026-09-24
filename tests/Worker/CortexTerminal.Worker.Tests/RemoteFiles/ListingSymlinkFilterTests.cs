using CortexTerminal.Worker.RemoteFiles;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace CortexTerminal.Worker.Tests.RemoteFiles;

/// <summary>
/// 列表过滤：逃逸出根的符号链接不展示（点了只会 400），指向根内部的链接保留。
/// Windows 创建 symlink 需要特权，跳过。
/// </summary>
public class ListingSymlinkFilterTests
{
    private readonly string _root = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".corterm-test", $"listing-{Guid.NewGuid():N}");

    public ListingSymlinkFilterTests()
    {
        Directory.CreateDirectory(Path.Combine(_root, "real-dir"));
        File.WriteAllText(Path.Combine(_root, "file.txt"), "hi");
    }

    private void CreateLink(string name, string target)
    {
        Directory.CreateSymbolicLink(Path.Combine(_root, name), target);
    }

    [Fact]
    public void EscapingSymlink_IsNotListed()
    {
        if (OperatingSystem.IsWindows()) return;
        var outside = Path.Combine(Path.GetDirectoryName(_root)!, "outside-target");
        Directory.CreateDirectory(outside);
        CreateLink("escape", outside);
        CreateLink("inward", "real-dir");

        var result = new RemoteDirectoryLister(_root, 500).List("");

        result.Error.Should().BeNull();
        var names = result.Listing!.Entries.Select(e => e.Name).ToList();
        names.Should().Contain("real-dir");
        names.Should().Contain("inward");   // 指向根内部的链接保留
        names.Should().NotContain("escape"); // 逃逸链接被过滤
        names.Should().NotContain("outside-target");
    }
}
