using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using Microsoft.AspNetCore.SignalR;

namespace CortexTerminal.Gateway.Hubs;

public sealed class WorkerHub(IWorkerRegistry workers, ISessionCoordinator sessions) : Hub
{
    public void RegisterWorker(string workerId)
        => workers.Register(workerId, Context.ConnectionId);

    public override Task OnDisconnectedAsync(Exception? exception)
    {
        // In Phase 1, workers just unregister on disconnect
        return base.OnDisconnectedAsync(exception);
    }

    public async Task ForwardStdout(TerminalChunk chunk)
    {
        if (sessions.TryGetSession(chunk.SessionId, out var session))
        {
            await Clients.Client(session.WorkerConnectionId).SendAsync("StdoutChunk", chunk);
        }
    }

    public async Task ForwardStderr(TerminalChunk chunk)
    {
        if (sessions.TryGetSession(chunk.SessionId, out var session))
        {
            await Clients.Client(session.WorkerConnectionId).SendAsync("StderrChunk", chunk);
        }
    }
}
