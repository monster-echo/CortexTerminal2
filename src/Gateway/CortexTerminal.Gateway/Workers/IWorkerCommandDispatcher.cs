using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;

namespace CortexTerminal.Gateway.Workers;

public interface IWorkerCommandDispatcher
{
    Task StartSessionAsync(string workerConnectionId, StartSessionCommand command, CancellationToken cancellationToken);
    Task WriteInputAsync(string workerConnectionId, WriteInputFrame frame, CancellationToken cancellationToken);
    Task ProbeLatencyAsync(string workerConnectionId, LatencyProbeFrame frame, CancellationToken cancellationToken);
    Task ResizeSessionAsync(string workerConnectionId, ResizePtyRequest request, CancellationToken cancellationToken);
    Task CloseSessionAsync(string workerConnectionId, CloseSessionRequest request, CancellationToken cancellationToken);
    Task UpgradeWorkerAsync(string workerConnectionId, UpgradeWorkerCommand command, CancellationToken cancellationToken);
}
