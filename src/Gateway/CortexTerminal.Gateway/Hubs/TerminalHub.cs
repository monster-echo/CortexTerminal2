using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace CortexTerminal.Gateway.Hubs;

[Authorize]
public sealed class TerminalHub(
    ISessionCoordinator sessions,
    IReplayCache replayCache,
    TimeProvider timeProvider,
    IWorkerCommandDispatcher workerCommands,
    ISessionLaunchCoordinator sessionLaunchCoordinator) : Hub
{
    public Task<CreateSessionResult> CreateSession(CreateSessionRequest request)
        => CreateSessionCoreAsync(request, Context.ConnectionAborted);

    public Task DetachSession(string sessionId)
        => DetachSessionCoreAsync(sessionId, Context.ConnectionAborted);

    public Task<ReattachSessionResult> ReattachSession(ReattachSessionRequest request)
        => ReattachSessionCoreAsync(request, Context.ConnectionAborted);

    private async Task<CreateSessionResult> CreateSessionCoreAsync(CreateSessionRequest request, CancellationToken cancellationToken)
        => await sessionLaunchCoordinator.CreateSessionAsync(
            Context.UserIdentifier ?? "unknown",
            request,
            Context.ConnectionId,
            cancellationToken);

    private async Task DetachSessionCoreAsync(string sessionId, CancellationToken cancellationToken)
    {
        var now = timeProvider.GetUtcNow();
        await sessions.DetachSessionAsync(Context.UserIdentifier ?? "unknown", sessionId, now, cancellationToken);
        await Clients.Caller.SendAsync("SessionDetached", new SessionDetachedEvent(sessionId, now.AddMinutes(5)), cancellationToken);
    }

    private async Task<ReattachSessionResult> ReattachSessionCoreAsync(ReattachSessionRequest request, CancellationToken cancellationToken)
    {
        var result = await sessions.ReattachSessionAsync(
            Context.UserIdentifier ?? "unknown",
            request,
            Context.ConnectionId,
            timeProvider.GetUtcNow(),
            cancellationToken);

        if (!result.IsSuccess)
        {
            return result;
        }

        try
        {
            await replayCache.ReplayWhileLockedAsync(request.SessionId, async snapshot =>
            {
                await Clients.Caller.SendAsync("SessionReattached", new SessionReattachedEvent(request.SessionId), cancellationToken);
                foreach (var chunk in snapshot)
                {
                    await Clients.Caller.SendAsync("ReplayChunk", chunk, cancellationToken);
                }

                await Clients.Caller.SendAsync("ReplayCompleted", new ReplayCompleted(request.SessionId), cancellationToken);
                sessions.MarkReplayCompleted(request.SessionId, Context.ConnectionId);
            }, cancellationToken);
        }
        catch
        {
            await sessions.DetachSessionAsync(Context.UserIdentifier ?? "unknown", request.SessionId, timeProvider.GetUtcNow(), cancellationToken);
            throw;
        }

        return result;
    }

    public async Task WriteInput(WriteInputFrame frame)
    {
        var session = RequireOwnedSession(frame.SessionId);
        await workerCommands.WriteInputAsync(session.WorkerConnectionId, frame, Context.ConnectionAborted);
    }

    public async Task ProbeLatency(LatencyProbeFrame frame)
    {
        var session = RequireOwnedSession(frame.SessionId);
        await workerCommands.ProbeLatencyAsync(session.WorkerConnectionId, frame, Context.ConnectionAborted);
    }

    public async Task ResizeSession(ResizePtyRequest request)
    {
        var session = RequireOwnedSession(request.SessionId);
        await workerCommands.ResizeSessionAsync(session.WorkerConnectionId, request, Context.ConnectionAborted);
    }

    public async Task CloseSession(CloseSessionRequest request)
    {
        var session = RequireOwnedSession(request.SessionId);
        await workerCommands.CloseSessionAsync(session.WorkerConnectionId, request, Context.ConnectionAborted);
    }

    private SessionRecord RequireOwnedSession(string sessionId)
    {
        if (!sessions.TryGetSession(sessionId, out var session))
        {
            throw new HubException("Unknown session.");
        }

        if (session.AttachmentState != SessionAttachmentState.Attached || session.AttachedClientConnectionId is null)
        {
            throw new HubException("Session is not attached.");
        }

        if (session.AttachedClientConnectionId != Context.ConnectionId)
        {
            throw new HubException("Session is attached to a different client.");
        }

        return session;
    }
}
