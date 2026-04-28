using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using Microsoft.AspNetCore.SignalR.Client;

namespace CortexTerminal.Worker.Registration;

public sealed class WorkerGatewayClient : IWorkerGatewayClient
{
    private readonly object _sync = new();
    private readonly HubConnection _connection;
    private event Func<string?, Task>? Reconnected;

    public WorkerGatewayClient(HubConnection connection)
    {
        _connection = connection;
        connection.Reconnected += HandleReconnectedAsync;
    }

    public Task StartAsync(CancellationToken cancellationToken)
        => _connection.StartAsync(cancellationToken);

    public Task RegisterAsync(string workerId, CancellationToken cancellationToken)
        => _connection.InvokeAsync("RegisterWorker", workerId, cancellationToken);

    public IDisposable OnStartSession(Func<StartSessionCommand, Task> handler)
        => _connection.On<StartSessionCommand>("StartSession", handler);

    public IDisposable OnWriteInput(Func<WriteInputFrame, Task> handler)
        => _connection.On<WriteInputFrame>("WriteInput", handler);

    public IDisposable OnLatencyProbe(Func<LatencyProbeFrame, Task> handler)
        => _connection.On<LatencyProbeFrame>("ProbeLatency", handler);

    public IDisposable OnResizeSession(Func<ResizePtyRequest, Task> handler)
        => _connection.On<ResizePtyRequest>("ResizeSession", handler);

    public IDisposable OnCloseSession(Func<CloseSessionRequest, Task> handler)
        => _connection.On<CloseSessionRequest>("CloseSession", handler);

    public IDisposable OnReconnected(Func<string?, Task> handler)
    {
        lock (_sync)
        {
            Reconnected += handler;
        }

        return new CallbackSubscription(() =>
        {
            lock (_sync)
            {
                Reconnected -= handler;
            }
        });
    }

    public Task ForwardStdoutAsync(TerminalChunk chunk, CancellationToken cancellationToken)
        => _connection.InvokeAsync("ForwardStdout", chunk, cancellationToken);

    public Task ForwardStderrAsync(TerminalChunk chunk, CancellationToken cancellationToken)
        => _connection.InvokeAsync("ForwardStderr", chunk, cancellationToken);

    public Task ForwardLatencyProbeAsync(LatencyProbeFrame frame, CancellationToken cancellationToken)
        => _connection.InvokeAsync("ForwardLatencyProbe", frame, cancellationToken);

    public Task ForwardExitedAsync(SessionExited evt, CancellationToken cancellationToken)
        => _connection.InvokeAsync("SessionExited", evt, cancellationToken);

    public Task ForwardStartFailedAsync(SessionStartFailedEvent evt, CancellationToken cancellationToken)
        => _connection.InvokeAsync("SessionStartFailed", evt, cancellationToken);

    public ValueTask DisposeAsync() => _connection.DisposeAsync();

    private async Task HandleReconnectedAsync(string? connectionId)
    {
        Func<string?, Task>? handlers;

        lock (_sync)
        {
            handlers = Reconnected;
        }

        if (handlers is null)
        {
            return;
        }

        await handlers(connectionId);
    }

    private sealed class CallbackSubscription(Action dispose) : IDisposable
    {
        public void Dispose() => dispose();
    }

}
