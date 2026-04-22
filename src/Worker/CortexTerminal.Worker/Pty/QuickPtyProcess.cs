using System.Runtime.CompilerServices;
using Pty.Net;

namespace CortexTerminal.Worker.Pty;

internal sealed class QuickPtyProcess : IPtyProcess
{
    private readonly IPtyConnection _connection;
    private readonly TaskCompletionSource<int> _exitCode = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly Task _exitObserver;

    public QuickPtyProcess(IPtyConnection connection)
    {
        _connection = connection;
        _exitObserver = Task.Run(ObserveExit);
    }

    public async IAsyncEnumerable<byte[]> ReadStdoutAsync([EnumeratorCancellation] CancellationToken cancellationToken)
    {
        var buffer = new byte[4096];
        while (true)
        {
            var count = await _connection.ReaderStream.ReadAsync(buffer, 0, buffer.Length, cancellationToken);
            if (count == 0)
            {
                yield break;
            }

            var chunk = new byte[count];
            Buffer.BlockCopy(buffer, 0, chunk, 0, count);
            yield return chunk;
        }
    }

    public IAsyncEnumerable<byte[]> ReadStderrAsync(CancellationToken cancellationToken)
    {
        return AsyncEnumerable.Empty<byte[]>();
    }

    public Task WriteAsync(byte[] payload, CancellationToken cancellationToken)
        => _connection.WriterStream.WriteAsync(payload, 0, payload.Length, cancellationToken);

    public Task ResizeAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        _connection.Resize(columns, rows);
        return Task.CompletedTask;
    }

    public Task<int> WaitForExitAsync(CancellationToken cancellationToken) => _exitCode.Task.WaitAsync(cancellationToken);

    public async ValueTask DisposeAsync()
    {
        if (!_exitCode.Task.IsCompleted)
        {
            _connection.Dispose();
        }

        await _exitObserver;
    }

    private void ObserveExit()
    {
        if (_connection.WaitForExit(Timeout.Infinite))
        {
            _exitCode.TrySetResult(_connection.ExitCode);
        }
    }
}
