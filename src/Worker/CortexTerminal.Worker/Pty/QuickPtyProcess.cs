using System.Runtime.CompilerServices;
using Pty.Net;

namespace CortexTerminal.Worker.Pty;

internal sealed class QuickPtyProcess(IPtyConnection connection) : IPtyProcess
{
    public async IAsyncEnumerable<byte[]> ReadStdoutAsync([EnumeratorCancellation] CancellationToken cancellationToken)
    {
        var buffer = new byte[4096];
        while (true)
        {
            var count = await connection.ReaderStream.ReadAsync(buffer, 0, buffer.Length, cancellationToken);
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
        => connection.WriterStream.WriteAsync(payload, 0, payload.Length, cancellationToken);

    public Task ResizeAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        connection.Resize(columns, rows);
        return Task.CompletedTask;
    }

    public Task<int> WaitForExitAsync(CancellationToken cancellationToken)
    {
        var completion = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously);
        connection.ProcessExited += (_, _) => completion.TrySetResult(connection.ExitCode);
        using var _ = cancellationToken.Register(() => completion.TrySetCanceled(cancellationToken));
        return completion.Task;
    }

    public ValueTask DisposeAsync()
    {
        connection.Dispose();
        return ValueTask.CompletedTask;
    }
}
