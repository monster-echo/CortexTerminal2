using CortexTerminal.Contracts.Streaming;

namespace CortexTerminal.Worker.Pty;

public sealed class PtySession(IPtyHost host)
{
    private IPtyProcess? _process;

    public async Task<IPtyProcess> StartAsync(string sessionId, int columns, int rows, CancellationToken cancellationToken)
    {
        _process = await host.StartAsync(columns, rows, cancellationToken);
        return _process;
    }

    public async IAsyncEnumerable<TerminalChunk> ReadStdoutChunksAsync(string sessionId, [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken)
    {
        if (_process is null) yield break;
        await foreach (var data in _process.ReadStdoutAsync(cancellationToken))
        {
            yield return new TerminalChunk(sessionId, "stdout", data);
        }
    }

    public async IAsyncEnumerable<TerminalChunk> ReadStderrChunksAsync(string sessionId, [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken)
    {
        if (_process is null) yield break;
        await foreach (var data in _process.ReadStderrAsync(cancellationToken))
        {
            yield return new TerminalChunk(sessionId, "stderr", data);
        }
    }
}
