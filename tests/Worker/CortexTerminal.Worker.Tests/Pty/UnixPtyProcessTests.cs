using System.Runtime.CompilerServices;
using System.Reflection;
using System.Text;
using System.Threading.Channels;
using CortexTerminal.Worker.Pty;
using FluentAssertions;
using Porta.Pty;

namespace CortexTerminal.Worker.Tests.Pty;

public sealed class UnixPtyProcessTests
{
    [Fact]
    public async Task ReadStdoutAsync_YieldsMultipleChunksInOrder()
    {
        var connection = new FakeConnection();
        connection.Reader.Enqueue("hello ");
        connection.Reader.Enqueue("world");
        connection.Reader.Complete();

        await using var process = CreateProcess(connection);

        var chunks = new List<string>();
        await foreach (var chunk in process.ReadStdoutAsync(CancellationToken.None))
        {
            chunks.Add(Encoding.UTF8.GetString(chunk));
        }

        chunks.Should().Equal("hello ", "world");
    }

    [Fact]
    public async Task ReadStdoutAsync_RespectsCancellationWhileWaitingForData()
    {
        var connection = new FakeConnection();
        await using var process = CreateProcess(connection);
        using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(100));

        var read = async () =>
        {
            await foreach (var _ in process.ReadStdoutAsync(cts.Token))
            {
            }
        };

        await read.Should().ThrowAsync<OperationCanceledException>();
    }

    [Fact]
    public async Task WriteAsync_WritesBytesAndFlushesWriter()
    {
        var connection = new FakeConnection();
        await using var process = CreateProcess(connection);
        var payload = Encoding.UTF8.GetBytes("echo hi\r");

        await process.WriteAsync(payload, CancellationToken.None);

        connection.Writer.Writes.Should().ContainSingle().Which.Should().Equal(payload);
        connection.Writer.FlushCount.Should().Be(1);
    }

    [Fact]
    public async Task ResizeAsync_ForwardsDimensionsToConnection()
    {
        var connection = new FakeConnection();
        await using var process = CreateProcess(connection);

        await process.ResizeAsync(132, 43, CancellationToken.None);

        connection.LastCols.Should().Be(132);
        connection.LastRows.Should().Be(43);
    }

    [Fact]
    public async Task WaitForExitAsync_CompletesFromProcessExitedEvent()
    {
        var connection = new FakeConnection();
        await using var process = CreateProcess(connection);

        var waitTask = process.WaitForExitAsync(CancellationToken.None);
        connection.Complete(exitCode: 17, raiseEvent: true);

        var exitCode = await waitTask;

        exitCode.Should().Be(17);
    }

    [Fact]
    public async Task WaitForExitAsync_CompletesFromWaitLoopWithoutEvent()
    {
        var connection = new FakeConnection();
        await using var process = CreateProcess(connection);

        var waitTask = process.WaitForExitAsync(CancellationToken.None);
        connection.Complete(exitCode: 23, raiseEvent: false);

        var exitCode = await waitTask;

        exitCode.Should().Be(23);
    }

    [Fact]
    public async Task DisposeAsync_SwallowsInvalidOperationExceptionFromConnectionDisposeRace()
    {
        var connection = new FakeConnection { ThrowOnDispose = true };
        await using var process = CreateProcess(connection);

        var dispose = async () => await process.DisposeAsync();

        await dispose.Should().NotThrowAsync();
    }

    [Fact]
    public async Task ReadStderrAsync_IsEmptyForUnifiedPtyStream()
    {
        var connection = new FakeConnection();
        await using var process = CreateProcess(connection);

        var stderrChunks = new List<byte[]>();
        await foreach (var chunk in process.ReadStderrAsync(CancellationToken.None))
        {
            stderrChunks.Add(chunk);
        }

        stderrChunks.Should().BeEmpty();
    }

    private static IPtyProcess CreateProcess(IPtyConnection connection)
    {
        var processType = typeof(UnixPtyHost).Assembly.GetType("CortexTerminal.Worker.Pty.UnixPtyProcess", throwOnError: true)!;
        return (IPtyProcess)Activator.CreateInstance(processType, connection)!;
    }
}

internal sealed class FakeConnection : IPtyConnection
{
    private readonly ManualResetEventSlim _exited = new(false);

    public FakeReadableStream Reader { get; } = new();
    public FakeWritableStream Writer { get; } = new();
    public bool ThrowOnDispose { get; set; }
    public int LastCols { get; private set; }
    public int LastRows { get; private set; }

    public Stream ReaderStream => Reader;
    public Stream WriterStream => Writer;
    public int Pid => 4242;
    public int ExitCode { get; private set; }
    public event EventHandler<PtyExitedEventArgs>? ProcessExited;

    public void Complete(int exitCode, bool raiseEvent)
    {
        ExitCode = exitCode;
        _exited.Set();
        Reader.Complete();

        if (raiseEvent)
        {
            ProcessExited?.Invoke(this, CreateExitArgs(exitCode));
        }
    }

    private static PtyExitedEventArgs CreateExitArgs(int exitCode)
    {
        var intCtor = typeof(PtyExitedEventArgs).GetConstructor(
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
            binder: null,
            [typeof(int)],
            modifiers: null);

        if (intCtor?.Invoke([exitCode]) is PtyExitedEventArgs argsFromCtor)
        {
            return argsFromCtor;
        }

        var defaultCtor = typeof(PtyExitedEventArgs).GetConstructor(
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
            binder: null,
            Type.EmptyTypes,
            modifiers: null);

        if (defaultCtor?.Invoke([]) is PtyExitedEventArgs argsFromDefaultCtor)
        {
            argsFromDefaultCtor.ExitCode = exitCode;
            return argsFromDefaultCtor;
        }

        throw new InvalidOperationException("Could not construct PtyExitedEventArgs for test event simulation.");
    }

    public void Dispose()
    {
        _exited.Set();
        Reader.Complete();

        if (ThrowOnDispose)
        {
            throw new InvalidOperationException("simulated dispose race");
        }
    }

    public void Kill()
    {
        Complete(exitCode: -1, raiseEvent: true);
    }

    public void Resize(int cols, int rows)
    {
        LastCols = cols;
        LastRows = rows;
    }

    public bool WaitForExit(int milliseconds)
        => milliseconds == Timeout.Infinite
            ? _exited.Wait(Timeout.Infinite)
            : _exited.Wait(milliseconds);
}

internal sealed class FakeReadableStream : Stream
{
    private readonly Channel<byte[]> _channel = Channel.CreateUnbounded<byte[]>();
    private byte[]? _current;
    private int _offset;

    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => throw new NotSupportedException();
    public override long Position
    {
        get => throw new NotSupportedException();
        set => throw new NotSupportedException();
    }

    public void Enqueue(string text)
        => _channel.Writer.TryWrite(Encoding.UTF8.GetBytes(text));

    public void Complete()
        => _channel.Writer.TryComplete();

    public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
    {
        while (true)
        {
            if (_current is not null && _offset < _current.Length)
            {
                var count = Math.Min(buffer.Length, _current.Length - _offset);
                _current.AsMemory(_offset, count).CopyTo(buffer);
                _offset += count;

                if (_offset >= _current.Length)
                {
                    _current = null;
                    _offset = 0;
                }

                return count;
            }

            if (!await _channel.Reader.WaitToReadAsync(cancellationToken))
            {
                return 0;
            }

            if (_channel.Reader.TryRead(out var next))
            {
                _current = next;
                _offset = 0;
            }
        }
    }

    public override int Read(byte[] buffer, int offset, int count)
        => throw new NotSupportedException();

    public override void Flush()
    {
    }

    public override long Seek(long offset, SeekOrigin origin)
        => throw new NotSupportedException();

    public override void SetLength(long value)
        => throw new NotSupportedException();

    public override void Write(byte[] buffer, int offset, int count)
        => throw new NotSupportedException();
}

internal sealed class FakeWritableStream : Stream
{
    public List<byte[]> Writes { get; } = [];
    public int FlushCount { get; private set; }

    public override bool CanRead => false;
    public override bool CanSeek => false;
    public override bool CanWrite => true;
    public override long Length => throw new NotSupportedException();
    public override long Position
    {
        get => throw new NotSupportedException();
        set => throw new NotSupportedException();
    }

    public override Task WriteAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
    {
        Writes.Add(buffer.Skip(offset).Take(count).ToArray());
        return Task.CompletedTask;
    }

    public override Task FlushAsync(CancellationToken cancellationToken)
    {
        FlushCount++;
        return Task.CompletedTask;
    }

    public override void Flush()
    {
        FlushCount++;
    }

    public override int Read(byte[] buffer, int offset, int count)
        => throw new NotSupportedException();

    public override long Seek(long offset, SeekOrigin origin)
        => throw new NotSupportedException();

    public override void SetLength(long value)
        => throw new NotSupportedException();

    public override void Write(byte[] buffer, int offset, int count)
        => throw new NotSupportedException();
}