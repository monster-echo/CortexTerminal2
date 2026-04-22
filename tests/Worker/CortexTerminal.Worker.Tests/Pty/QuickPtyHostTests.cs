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

        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));

        var host = new QuickPtyHost();
        await using var process = await host.StartAsync(120, 40, cts.Token);

        await process.WriteAsync("echo hello\n"u8.ToArray(), cts.Token);
        var output = await ReadUntilAsync(process.ReadStdoutAsync(cts.Token), "hello", cts.Token);

        output.Should().Contain("hello");
    }

    [Fact]
    public async Task ResizeAsync_UpdatesRunningPty()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));

        var host = new QuickPtyHost();
        await using var process = await host.StartAsync(120, 40, cts.Token);

        await process.ResizeAsync(100, 30, cts.Token);
        await process.WriteAsync("stty size\n"u8.ToArray(), cts.Token);
        var output = await ReadUntilAsync(process.ReadStdoutAsync(cts.Token), "30 100", cts.Token);

        output.Should().Contain("30 100");
    }

    [Fact]
    public async Task StartAsync_ThrowsExplicitError_WhenLinuxRuntimeSupportIsMissing()
    {
        if (!OperatingSystem.IsLinux())
        {
            return;
        }

        var prev = Environment.GetEnvironmentVariable("DOTNET_EnableWriteXorExecute");
        try
        {
            Environment.SetEnvironmentVariable("DOTNET_EnableWriteXorExecute", null);
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));

            var host = new QuickPtyHost();
            var start = () => host.StartAsync(120, 40, cts.Token);

            await start.Should().ThrowAsync<PtySupportException>()
                .WithMessage("*pty-not-supported-on-platform*");
        }
        finally
        {
            Environment.SetEnvironmentVariable("DOTNET_EnableWriteXorExecute", prev);
        }
    }

    private static async Task<string> ReadUntilAsync(
        IAsyncEnumerable<byte[]> source,
        string expected,
        CancellationToken cancellationToken)
    {
        // Bound the wait to avoid hanging tests indefinitely.
        using var timeoutCts = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutCts.Token);

        var builder = new StringBuilder();
        try
        {
            await foreach (var chunk in source.WithCancellation(linked.Token))
            {
                builder.Append(Encoding.UTF8.GetString(chunk));
                if (builder.ToString().Contains(expected, StringComparison.Ordinal))
                {
                    break;
                }
            }
        }
        catch (OperationCanceledException) when (timeoutCts.IsCancellationRequested)
        {
            throw new TimeoutException($"Timed out waiting for \"{expected}\"");
        }

        return builder.ToString();
    }
}
