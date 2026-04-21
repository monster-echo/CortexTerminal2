using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using Microsoft.AspNetCore.SignalR;

namespace CortexTerminal.Gateway.Hubs;

public sealed class WorkerHub(
    IWorkerRegistry workers,
    ISessionCoordinator sessions,
    IReplayCache replayCache,
    IHubContext<TerminalHub> terminalHubContext) : Hub
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
        if (!sessions.TryGetSession(chunk.SessionId, out var session) ||
            session.WorkerConnectionId != Context.ConnectionId)
        {
            return;
        }

        await replayCache.AppendAsync(new ReplayChunk(chunk.SessionId, chunk.Stream, chunk.Payload), Context.ConnectionAborted);

        if (!sessions.TryGetSession(chunk.SessionId, out session) ||
            session.WorkerConnectionId != Context.ConnectionId)
        {
            return;
        }

        if (session.AttachmentState != SessionAttachmentState.Attached ||
            session.AttachedClientConnectionId is null ||
            session.ReplayPending)
        {
            return;
        }

        await terminalHubContext.Clients.Client(session.AttachedClientConnectionId).SendAsync("StdoutChunk", chunk);
    }

    public async Task ForwardStderr(TerminalChunk chunk)
    {
        if (!sessions.TryGetSession(chunk.SessionId, out var session) ||
            session.WorkerConnectionId != Context.ConnectionId)
        {
            return;
        }

        await replayCache.AppendAsync(new ReplayChunk(chunk.SessionId, chunk.Stream, chunk.Payload), Context.ConnectionAborted);

        if (!sessions.TryGetSession(chunk.SessionId, out session) ||
            session.WorkerConnectionId != Context.ConnectionId)
        {
            return;
        }

        if (session.AttachmentState != SessionAttachmentState.Attached ||
            session.AttachedClientConnectionId is null ||
            session.ReplayPending)
        {
            return;
        }

        await terminalHubContext.Clients.Client(session.AttachedClientConnectionId).SendAsync("StderrChunk", chunk);
    }

    public async Task SessionStartFailed(SessionStartFailedEvent evt)
    {
        if (!sessions.TryGetSession(evt.SessionId, out var session) || session.WorkerConnectionId != Context.ConnectionId)
        {
            return;
        }

        sessions.MarkSessionStartFailed(evt.SessionId, evt.Reason);
        replayCache.Clear(evt.SessionId);

        if (session.AttachedClientConnectionId is not null)
        {
            await terminalHubContext.Clients.Client(session.AttachedClientConnectionId).SendAsync("SessionStartFailed", evt);
        }
    }

    public async Task SessionExited(SessionExited evt)
    {
        if (!sessions.TryGetSession(evt.SessionId, out var session) || session.WorkerConnectionId != Context.ConnectionId)
        {
            return;
        }

        var attachedClientConnectionId = session.AttachedClientConnectionId;
        sessions.MarkSessionExited(evt.SessionId, evt.ExitCode, evt.Reason);
        replayCache.Clear(evt.SessionId);

        if (attachedClientConnectionId is not null)
        {
            await terminalHubContext.Clients.Client(attachedClientConnectionId).SendAsync("SessionExited", evt);
        }
    }
}
