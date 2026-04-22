namespace CortexTerminal.Worker.Pty;

public sealed class UnixPtyHost : IPtyHost
{
    private readonly QuickPtyHost _inner = new();

    public Task<IPtyProcess> StartAsync(int columns, int rows, CancellationToken cancellationToken)
        => _inner.StartAsync(columns, rows, cancellationToken);
}
