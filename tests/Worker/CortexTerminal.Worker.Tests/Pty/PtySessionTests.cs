using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Pty;
using FluentAssertions;
using System.Runtime.CompilerServices;
using Xunit;

namespace CortexTerminal.Worker.Tests.Pty;

public sealed class PtySessionTests
{
    [Fact]
    public async Task StartAsync_ForwardsStdoutAndStderrSeparately()
    {
        var fakeHost = new FakePtyHost(stdout: [0x6F, 0x6B], stderr: [0x62, 0x61, 0x64]);
        var session = new PtySession(fakeHost);

        await session.StartAsync("sess_1", 120, 40, CancellationToken.None);

        var stdoutChunks = new List<TerminalChunk>();
        await foreach (var chunk in session.ReadStdoutChunksAsync("sess_1", CancellationToken.None))
        {
            stdoutChunks.Add(chunk);
        }

        var stderrChunks = new List<TerminalChunk>();
        await foreach (var chunk in session.ReadStderrChunksAsync("sess_1", CancellationToken.None))
        {
            stderrChunks.Add(chunk);
        }

        stdoutChunks.Should().ContainSingle(x => x.Stream == "stdout");
        stderrChunks.Should().ContainSingle(x => x.Stream == "stderr");
    }

    [Fact]
    public async Task WriteAsync_ForwardsBytesToProcess()
    {
        var fakeHost = new FakePtyHost(stdout: [], stderr: []);
        var session = new PtySession(fakeHost);

        var process = await session.StartAsync("sess_1", 120, 40, CancellationToken.None);
        var payload = new byte[] { 0x09, 0x03 };
        await process.WriteAsync(payload, CancellationToken.None);

        ((FakePtyProcess)process).WrittenData.Should().ContainSingle().Which.Should().Equal(payload);
    }

    [Fact]
    public async Task ResizeAsync_ForwardsNewDimensions()
    {
        var fakeHost = new FakePtyHost(stdout: [], stderr: []);
        var session = new PtySession(fakeHost);

        var process = await session.StartAsync("sess_1", 120, 40, CancellationToken.None);
        await process.ResizeAsync(140, 50, CancellationToken.None);

        var fake = (FakePtyProcess)process;
        fake.LastColumns.Should().Be(140);
        fake.LastRows.Should().Be(50);
    }
}

internal sealed class FakePtyHost(byte[] stdout, byte[] stderr) : IPtyHost
{
    public Task<IPtyProcess> StartAsync(int columns, int rows, CancellationToken cancellationToken)
        => Task.FromResult<IPtyProcess>(new FakePtyProcess(stdout, stderr));
}

internal sealed class FakePtyProcess(byte[] stdout, byte[] stderr) : IPtyProcess
{
    public List<byte[]> WrittenData { get; } = [];
    public int LastColumns { get; private set; }
    public int LastRows { get; private set; }

    public async IAsyncEnumerable<byte[]> ReadStdoutAsync([EnumeratorCancellation] CancellationToken cancellationToken)
    {
        if (stdout.Length > 0)
        {
            yield return stdout;
        }
        await Task.CompletedTask;
    }

    public async IAsyncEnumerable<byte[]> ReadStderrAsync([EnumeratorCancellation] CancellationToken cancellationToken)
    {
        if (stderr.Length > 0)
        {
            yield return stderr;
        }
        await Task.CompletedTask;
    }

    public Task WriteAsync(byte[] payload, CancellationToken cancellationToken)
    {
        WrittenData.Add(payload.ToArray());
        return Task.CompletedTask;
    }

    public Task ResizeAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        LastColumns = columns;
        LastRows = rows;
        return Task.CompletedTask;
    }

    public Task<int> WaitForExitAsync(CancellationToken cancellationToken) => Task.FromResult(0);

    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
}
