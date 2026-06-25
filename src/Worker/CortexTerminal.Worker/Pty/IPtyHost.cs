namespace CortexTerminal.Worker.Pty;

public interface IPtyHost
{
    Task<IPtyProcess> StartAsync(int columns, int rows, CancellationToken cancellationToken);
    Task<IPtyProcess> StartAsync(int columns, int rows, IReadOnlyDictionary<string, string> environmentVariables, CancellationToken cancellationToken);
}

public interface IPtyProcess : IAsyncDisposable
{
    IAsyncEnumerable<byte[]> ReadStdoutAsync(CancellationToken cancellationToken);
    IAsyncEnumerable<byte[]> ReadStderrAsync(CancellationToken cancellationToken);
    Task WriteAsync(byte[] payload, CancellationToken cancellationToken);
    Task ResizeAsync(int columns, int rows, CancellationToken cancellationToken);
    Task<int> WaitForExitAsync(CancellationToken cancellationToken);
}
