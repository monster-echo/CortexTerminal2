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
    IWorkerCommandDispatcher workerCommands) : Hub
{
    public async Task<CreateSessionResult> CreateSession(CreateSessionRequest request, CancellationToken cancellationToken)
    {
        var result = await sessions.CreateSessionAsync(Context.UserIdentifier ?? "unknown", request, Context.ConnectionId, cancellationToken);
        if (!result.IsSuccess || result.Response is null || !sessions.TryGetSession(result.Response.SessionId, out var session))
        {
            return result;
        }

        try
        {
            await workerCommands.StartSessionAsync(session.WorkerConnectionId, new StartSessionCommand(session.SessionId, session.Columns, session.Rows), cancellationToken);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            sessions.MarkSessionStartFailed(session.SessionId, "worker-start-dispatch-failed");
            return CreateSessionResult.Failure("worker-start-dispatch-failed");
        }

        return result;
    }

    public async Task DetachSession(string sessionId, CancellationToken cancellationToken)
    {
        var now = timeProvider.GetUtcNow();
        await sessions.DetachSessionAsync(Context.UserIdentifier ?? "unknown", sessionId, now, cancellationToken);
        await Clients.Caller.SendAsync("SessionDetached", new SessionDetachedEvent(sessionId, now.AddMinutes(5)), cancellationToken);
    }

    public async Task<ReattachSessionResult> ReattachSession(ReattachSessionRequest request, CancellationToken cancellationToken)
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
