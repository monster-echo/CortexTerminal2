using CortexTerminal.Worker.Diagnostics;
using FluentAssertions;

namespace CortexTerminal.Worker.Tests.Diagnostics;

public sealed class DirectoryAccessProbeTests
{
    [Fact]
    public async Task ExistingDirectory_WithShellMetacharacters_IsCheckedAsAPath()
    {
        var root = Path.Combine(Path.GetTempPath(), "corterm-access-" + Guid.NewGuid().ToString("N"));
        var path = Path.Combine(root, "spaces ' ; $(not-a-command)");
        Directory.CreateDirectory(path);
        try
        {
            var result = await DirectoryAccessProbe.CheckAsync(path);
            result.State.Should().Be("accessible");
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Fact]
    public async Task MissingDirectory_IsNotReportedAsPermissionDenied()
    {
        var result = await DirectoryAccessProbe.CheckAsync(Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N")));
        result.State.Should().Be("unavailable");
    }

    [Fact]
    public async Task FileIsNotAWorkingDirectory()
    {
        var path = Path.GetTempFileName();
        try { (await DirectoryAccessProbe.CheckAsync(path)).State.Should().Be("unavailable"); }
        finally { File.Delete(path); }
    }
}
