using CortexTerminal.Worker.RemoteFiles;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Worker.Tests.RemoteFiles;

/// <summary>
/// 列表跟随符号链接（产品决策：用户建链接就是为了让它出现在那里）。
/// Windows 创建 symlink 需要特权，跳过。
/// </summary>
public class ListingFollowsSymlinksTests
{
    private readonly string _root = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".corterm-test", $"listing-{Guid.NewGuid():N}");

    public ListingFollowsSymlinksTests()
    {
        Directory.CreateDirectory(Path.Combine(_root, "real-dir"));
        File.WriteAllText(Path.Combine(_root, "file.txt"), "hi");
    }

    [Fact]
    public void Symlinks_AreListed_IncludingEscapingOnes()
    {
        if (OperatingSystem.IsWindows()) return;
        var outside = Path.Combine(Path.GetDirectoryName(_root)!, "outside-target");
        Directory.CreateDirectory(outside);
        File.WriteAllText(Path.Combine(outside, "target-file.txt"), "x");
        Directory.CreateSymbolicLink(Path.Combine(_root, "escape"), outside);
        Directory.CreateSymbolicLink(Path.Combine(_root, "inward"), Path.Combine(_root, "real-dir"));

        var result = new RemoteDirectoryLister(_root, 500).List("");

        result.Error.Should().BeNull();
        var names = result.Listing!.Entries.Select(e => e.Name).ToList();
        names.Should().Contain("real-dir");
        names.Should().Contain("inward");
        names.Should().Contain("escape"); // 逃逸链接照常展示，点击可进入目标
    }
}
