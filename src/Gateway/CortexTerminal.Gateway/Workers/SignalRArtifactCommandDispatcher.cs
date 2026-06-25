using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Hubs;
using Microsoft.AspNetCore.SignalR;

namespace CortexTerminal.Gateway.Workers;

public sealed class SignalRArtifactCommandDispatcher(IHubContext<WorkerHub> hubContext) : IArtifactCommandDispatcher
{
    public Task NotifyArtifactUploadedAsync(string workerConnectionId, NotifyArtifactUploadedFrame frame, CancellationToken ct)
        => hubContext.Clients.Client(workerConnectionId).SendAsync("NotifyArtifactUploaded", frame, ct);
}
