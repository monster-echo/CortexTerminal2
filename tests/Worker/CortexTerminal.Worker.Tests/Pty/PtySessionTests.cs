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
        var scrollbackBuffer = new ScrollbackBuffer(1024);
        var session = new PtySession(fakeHost, scrollbackBuffer);

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
        AssertChunks(
            scrollbackBuffer.Snapshot(),
            ("sess_1", "stdout", [0x6F, 0x6B]),
            ("sess_1", "stderr", [0x62, 0x61, 0x64]));
    }

    [Fact]
    public async Task StartAsync_CopiesStdoutIntoScrollbackBuffer()
    {
        var fakeHost = new FakePtyHost(stdout: [0x6F, 0x6B], stderr: []);
        var scrollbackBuffer = new ScrollbackBuffer(1024);
        var session = new PtySession(fakeHost, scrollbackBuffer);

        await session.StartAsync("sess_1", 120, 40, CancellationToken.None);
        var stdoutChunks = await ReadAllAsync(session.ReadStdoutChunksAsync("sess_1", CancellationToken.None));

        AssertChunks(stdoutChunks, ("sess_1", "stdout", [0x6F, 0x6B]));
        AssertChunks(scrollbackBuffer.Snapshot(), ("sess_1", "stdout", [0x6F, 0x6B]));
    }

    [Fact]
    public async Task StartAsync_CopiesStderrIntoScrollbackBuffer()
    {
        var fakeHost = new FakePtyHost(stdout: [], stderr: [0x62, 0x61, 0x64]);
        var scrollbackBuffer = new ScrollbackBuffer(1024);
        var session = new PtySession(fakeHost, scrollbackBuffer);

        await session.StartAsync("sess_1", 120, 40, CancellationToken.None);
        var stderrChunks = await ReadAllAsync(session.ReadStderrChunksAsync("sess_1", CancellationToken.None));

        AssertChunks(stderrChunks, ("sess_1", "stderr", [0x62, 0x61, 0x64]));
        AssertChunks(scrollbackBuffer.Snapshot(), ("sess_1", "stderr", [0x62, 0x61, 0x64]));
    }

    [Fact]
    public async Task ReadStdoutChunksAsync_AppendsChunkBeforeYieldingIt()
    {
        var fakeHost = new FakePtyHost(stdout: [0x6F, 0x6B], stderr: []);
        var scrollbackBuffer = new ScrollbackBuffer(1024);
        var session = new PtySession(fakeHost, scrollbackBuffer);

        await session.StartAsync("sess_1", 120, 40, CancellationToken.None);

        await using var enumerator = session.ReadStdoutChunksAsync("sess_1", CancellationToken.None).GetAsyncEnumerator();
        (await enumerator.MoveNextAsync()).Should().BeTrue();

        var firstChunk = enumerator.Current;
        AssertChunks(
            scrollbackBuffer.Snapshot(),
            (firstChunk.SessionId, firstChunk.Stream, firstChunk.Payload));
        firstChunk.Payload.Should().Equal([0x6F, 0x6B]);

        (await enumerator.MoveNextAsync()).Should().BeFalse();
    }

    [Fact]
    public async Task ReadStderrChunksAsync_AppendsChunkBeforeYieldingIt()
    {
        var fakeHost = new FakePtyHost(stdout: [], stderr: [0x62, 0x61, 0x64]);
        var scrollbackBuffer = new ScrollbackBuffer(1024);
        var session = new PtySession(fakeHost, scrollbackBuffer);

        await session.StartAsync("sess_1", 120, 40, CancellationToken.None);

        await using var enumerator = session.ReadStderrChunksAsync("sess_1", CancellationToken.None).GetAsyncEnumerator();
        (await enumerator.MoveNextAsync()).Should().BeTrue();

        var firstChunk = enumerator.Current;
        AssertChunks(
            scrollbackBuffer.Snapshot(),
            (firstChunk.SessionId, firstChunk.Stream, firstChunk.Payload));
        firstChunk.Payload.Should().Equal([0x62, 0x61, 0x64]);

        (await enumerator.MoveNextAsync()).Should().BeFalse();
    }

    [Fact]
    public async Task WriteAsync_ForwardsBytesToProcess()
    {
        var fakeHost = new FakePtyHost(stdout: [], stderr: []);
        var session = new PtySession(fakeHost, new ScrollbackBuffer(1024));

        var process = await session.StartAsync("sess_1", 120, 40, CancellationToken.None);
        var payload = new byte[] { 0x09, 0x03 };
        await process.WriteAsync(payload, CancellationToken.None);

        ((FakePtyProcess)process).WrittenData.Should().ContainSingle().Which.Should().Equal(payload);
    }

    [Fact]
    public async Task ResizeAsync_ForwardsNewDimensions()
    {
        var fakeHost = new FakePtyHost(stdout: [], stderr: []);
        var session = new PtySession(fakeHost, new ScrollbackBuffer(1024));

        var process = await session.StartAsync("sess_1", 120, 40, CancellationToken.None);
        await process.ResizeAsync(140, 50, CancellationToken.None);

        var fake = (FakePtyProcess)process;
        fake.LastColumns.Should().Be(140);
        fake.LastRows.Should().Be(50);
    }

    [Fact]
    public async Task ReadStdoutChunksAsync_PreservesMultipleChunkOrder()
    {
        var fakeHost = new SequencedFakePtyHost(stdoutChunks: [[0x61], [0x62, 0x63]], stderrChunks: []);
        var scrollbackBuffer = new ScrollbackBuffer(1024);
        var session = new PtySession(fakeHost, scrollbackBuffer);

        await session.StartAsync("sess_1", 120, 40, CancellationToken.None);
        var stdoutChunks = await ReadAllAsync(session.ReadStdoutChunksAsync("sess_1", CancellationToken.None));

        AssertChunks(
            stdoutChunks,
            ("sess_1", "stdout", [0x61]),
            ("sess_1", "stdout", [0x62, 0x63]));

        AssertChunks(
            scrollbackBuffer.Snapshot(),
            ("sess_1", "stdout", [0x61]),
            ("sess_1", "stdout", [0x62, 0x63]));
    }

    [Fact]
    public async Task ReadStdoutChunksAsync_WhenSessionNotStarted_YieldsNothing()
    {
        var session = new PtySession(new FakePtyHost([], []), new ScrollbackBuffer(1024));

        var stdoutChunks = await ReadAllAsync(session.ReadStdoutChunksAsync("sess_1", CancellationToken.None));

        stdoutChunks.Should().BeEmpty();
    }

    private static async Task<List<TerminalChunk>> ReadAllAsync(IAsyncEnumerable<TerminalChunk> source)
    {
        var chunks = new List<TerminalChunk>();
        await foreach (var chunk in source)
        {
            chunks.Add(chunk);
        }

        return chunks;
    }

    private static void AssertChunks(
        IReadOnlyList<TerminalChunk> actual,
        params (string SessionId, string Stream, byte[] Payload)[] expected)
    {
        actual.Should().HaveCount(expected.Length);

        for (var i = 0; i < expected.Length; i++)
        {
            actual[i].SessionId.Should().Be(expected[i].SessionId);
            actual[i].Stream.Should().Be(expected[i].Stream);
            actual[i].Payload.Should().Equal(expected[i].Payload);
        }
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

internal sealed class SequencedFakePtyHost(byte[][] stdoutChunks, byte[][] stderrChunks) : IPtyHost
{
    public Task<IPtyProcess> StartAsync(int columns, int rows, CancellationToken cancellationToken)
        => Task.FromResult<IPtyProcess>(new SequencedFakePtyProcess(stdoutChunks, stderrChunks));
}

internal sealed class SequencedFakePtyProcess(byte[][] stdoutChunks, byte[][] stderrChunks) : IPtyProcess
{
    public async IAsyncEnumerable<byte[]> ReadStdoutAsync([EnumeratorCancellation] CancellationToken cancellationToken)
    {
        foreach (var chunk in stdoutChunks)
        {
            yield return chunk;
            await Task.Yield();
        }
    }

    public async IAsyncEnumerable<byte[]> ReadStderrAsync([EnumeratorCancellation] CancellationToken cancellationToken)
    {
        foreach (var chunk in stderrChunks)
        {
            yield return chunk;
            await Task.Yield();
        }
    }

    public Task WriteAsync(byte[] payload, CancellationToken cancellationToken) => Task.CompletedTask;

    public Task ResizeAsync(int columns, int rows, CancellationToken cancellationToken) => Task.CompletedTask;

    public Task<int> WaitForExitAsync(CancellationToken cancellationToken) => Task.FromResult(0);

    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
}
