using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Hubs;
using Microsoft.AspNetCore.SignalR;

namespace CortexTerminal.Gateway.Workers;

public sealed class SignalRWorkerCommandDispatcher(IHubContext<WorkerHub> hubContext) : IWorkerCommandDispatcher
{
    public Task StartSessionAsync(string workerConnectionId, StartSessionCommand command, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).SendAsync("StartSession", command, cancellationToken);

    public Task WriteInputAsync(string workerConnectionId, WriteInputFrame frame, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).SendAsync("WriteInput", frame, cancellationToken);

    public Task ResizeSessionAsync(string workerConnectionId, ResizePtyRequest request, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).SendAsync("ResizeSession", request, cancellationToken);

    public Task CloseSessionAsync(string workerConnectionId, CloseSessionRequest request, CancellationToken cancellationToken)
        => hubContext.Clients.Client(workerConnectionId).SendAsync("CloseSession", request, cancellationToken);
}
