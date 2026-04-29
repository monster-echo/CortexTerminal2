using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;

namespace CortexTerminal.Worker.Registration;

public interface IWorkerGatewayClient : IAsyncDisposable
{
    Task StartAsync(CancellationToken cancellationToken);
    Task RegisterAsync(string workerId, CancellationToken cancellationToken);
    IDisposable OnStartSession(Func<StartSessionCommand, Task> handler);
    IDisposable OnWriteInput(Func<WriteInputFrame, Task> handler);
    IDisposable OnLatencyProbe(Func<LatencyProbeFrame, Task> handler);
    IDisposable OnResizeSession(Func<ResizePtyRequest, Task> handler);
    IDisposable OnCloseSession(Func<CloseSessionRequest, Task> handler);
    IDisposable OnUpgradeWorker(Func<UpgradeWorkerCommand, Task> handler);
    IDisposable OnReconnected(Func<string?, Task> handler);
    Task ForwardStdoutAsync(TerminalChunk chunk, CancellationToken cancellationToken);
    Task ForwardStderrAsync(TerminalChunk chunk, CancellationToken cancellationToken);
    Task ForwardLatencyProbeAsync(LatencyProbeFrame frame, CancellationToken cancellationToken);
    Task ForwardExitedAsync(SessionExited evt, CancellationToken cancellationToken);
    Task ForwardStartFailedAsync(SessionStartFailedEvent evt, CancellationToken cancellationToken);
    Task SendWorkerInfoAsync(WorkerInfoFrame info, CancellationToken ct);
}
