using System.IO;
using CortexTerminal.Worker.Pty;
using FluentAssertions;
using Pty.Net;

namespace CortexTerminal.Worker.Tests.Pty;

public sealed class QuickPtyProcessTests
{
    [Fact]
    public async Task WaitForExitAsync_CompletesWhenConnectionExits()
    {
        var connection = new FakePtyConnection();
        var processType = typeof(QuickPtyHost).Assembly.GetType("CortexTerminal.Worker.Pty.QuickPtyProcess", throwOnError: true)!;
        await using var process = (IPtyProcess)Activator.CreateInstance(processType, connection)!;

        var waitTask = process.WaitForExitAsync(CancellationToken.None);
        connection.Complete(exitCode: 0);

        var exitCode = await waitTask;

        exitCode.Should().Be(0);
    }
}

internal sealed class FakePtyConnection : IPtyConnection
{
    private readonly ManualResetEventSlim _exited = new(false);

    public Stream ReaderStream { get; } = new MemoryStream();
    public Stream WriterStream { get; } = new MemoryStream();
    public int Pid => 1234;
    public int ExitCode { get; private set; }
#pragma warning disable CS0067
    public event EventHandler<PtyExitedEventArgs>? ProcessExited;
#pragma warning restore CS0067

    public void Complete(int exitCode)
    {
        ExitCode = exitCode;
        _exited.Set();
    }

    public bool WaitForExit(int milliseconds)
    {
        return milliseconds == Timeout.Infinite
            ? _exited.Wait(Timeout.Infinite)
            : _exited.Wait(milliseconds);
    }

    public void Kill() => _exited.Set();

    public void Resize(int cols, int rows)
    {
    }

    public void Dispose() => _exited.Dispose();
}
