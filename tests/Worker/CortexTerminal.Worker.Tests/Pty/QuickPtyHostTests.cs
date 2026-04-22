using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using CortexTerminal.Worker.Pty;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Worker.Tests.Pty;

public sealed class QuickPtyHostTests
{
    [Fact]
    public async Task StartAsync_LaunchesInteractiveShell_AndEchoRoundTrips()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        var host = new QuickPtyHost();
        await using var process = await host.StartAsync(120, 40, CancellationToken.None);

        await process.WriteAsync("echo hello\n"u8.ToArray(), CancellationToken.None);
        var output = await ReadUntilAsync(process.ReadStdoutAsync(CancellationToken.None), "hello", CancellationToken.None);

        output.Should().Contain("hello");
    }

    [Fact]
    public async Task ResizeAsync_UpdatesRunningPty()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        var host = new QuickPtyHost();
        await using var process = await host.StartAsync(120, 40, CancellationToken.None);

        await process.ResizeAsync(100, 30, CancellationToken.None);
        await process.WriteAsync("stty size\n"u8.ToArray(), CancellationToken.None);
        var output = await ReadUntilAsync(process.ReadStdoutAsync(CancellationToken.None), "30 100", CancellationToken.None);

        output.Should().Contain("30 100");
    }

    [Fact]
    public async Task StartAsync_ThrowsExplicitError_WhenLinuxRuntimeSupportIsMissing()
    {
        if (!OperatingSystem.IsLinux())
        {
            return;
        }

        Environment.SetEnvironmentVariable("DOTNET_EnableWriteXorExecute", null);
        var host = new QuickPtyHost();
        var start = () => host.StartAsync(120, 40, CancellationToken.None);

        await start.Should().ThrowAsync<PtySupportException>()
            .WithMessage("*pty-not-supported-on-platform*");
    }

    private static async Task<string> ReadUntilAsync(
        IAsyncEnumerable<byte[]> source,
        string expected,
        CancellationToken cancellationToken)
    {
        var builder = new StringBuilder();
        await foreach (var chunk in source.WithCancellation(cancellationToken))
        {
            builder.Append(Encoding.UTF8.GetString(chunk));
            if (builder.ToString().Contains(expected, StringComparison.Ordinal))
            {
                break;
            }
        }

        return builder.ToString();
    }
}
