using System.Runtime.CompilerServices;
using Porta.Pty;

namespace CortexTerminal.Worker.Pty;

internal sealed class UnixPtyProcess : IPtyProcess
{
    private readonly IPtyConnection _connection;
    private readonly CancellationTokenSource _disposeCts = new();
    private readonly TaskCompletionSource<int> _exitCode = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly Task _exitObserver;
    private int _disposeState;

    public UnixPtyProcess(IPtyConnection connection)
    {
        _connection = connection;
        _connection.ProcessExited += OnExited;
        _exitObserver = Task.Run(ObserveExit);
    }

    public async IAsyncEnumerable<byte[]> ReadStdoutAsync([EnumeratorCancellation] CancellationToken cancellationToken)
    {
        await foreach (var chunk in ReadStreamAsync(_connection.ReaderStream, cancellationToken))
        {
            yield return chunk;
        }
    }

    public async IAsyncEnumerable<byte[]> ReadStderrAsync([EnumeratorCancellation] CancellationToken cancellationToken)
    {
        await Task.CompletedTask;
        yield break;
    }

    public async Task WriteAsync(byte[] payload, CancellationToken cancellationToken)
    {
        await _connection.WriterStream.WriteAsync(payload, 0, payload.Length, cancellationToken);
        await _connection.WriterStream.FlushAsync(cancellationToken);
    }

    public Task ResizeAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        _connection.Resize(columns, rows);
        return Task.CompletedTask;
    }

    public Task<int> WaitForExitAsync(CancellationToken cancellationToken)
        => _exitCode.Task.WaitAsync(cancellationToken);

    public async ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref _disposeState, 1) != 0)
        {
            return;
        }

        _disposeCts.Cancel();
        _connection.ProcessExited -= OnExited;

        if (!_exitCode.Task.IsCompleted)
        {
            try
            {
                _connection.Dispose();
            }
            catch (InvalidOperationException)
            {
                // Pty.Net on Unix may report EINVAL when the child already exited while disposal races with kill.
            }
        }

        await _exitObserver;
        _disposeCts.Dispose();
    }

    private void OnExited(object? sender, PtyExitedEventArgs args)
    {
        _exitCode.TrySetResult(args.ExitCode);
    }

    private void ObserveExit()
    {
        while (!_disposeCts.IsCancellationRequested)
        {
            if (_connection.WaitForExit(250))
            {
                _exitCode.TrySetResult(_connection.ExitCode);
                return;
            }
        }

        _exitCode.TrySetCanceled();
    }

    private static async IAsyncEnumerable<byte[]> ReadStreamAsync(
        Stream stream,
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        var buffer = new byte[4096];
        while (true)
        {
            var count = await stream.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken);
            if (count == 0)
            {
                yield break;
            }

            yield return buffer[..count].ToArray();
        }
    }
}