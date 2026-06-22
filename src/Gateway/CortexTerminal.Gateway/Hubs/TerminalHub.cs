using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Stats;
using CortexTerminal.Gateway.Workers;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace CortexTerminal.Gateway.Hubs;

[Authorize]
public sealed class TerminalHub(
    ISessionCoordinator sessions,
    ReplayCoordinator replayCoordinator,
    TimeProvider timeProvider,
    IWorkerCommandDispatcher workerCommands,
    ISessionLaunchCoordinator sessionLaunchCoordinator,
    IGatewayStatsService stats,
    ILogger<TerminalHub> logger) : Hub
{
    public override Task OnConnectedAsync()
    {
        stats.ClientConnected();
        return base.OnConnectedAsync();
    }

    public override Task OnDisconnectedAsync(Exception? exception)
    {
        stats.ClientDisconnected();
        return base.OnDisconnectedAsync(exception);
    }
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
        await Clients.Caller.SendAsync("SessionDetached", new SessionDetachedEvent(sessionId, DateTimeOffset.MaxValue), cancellationToken);
    }

    private async Task<ReattachSessionResult> ReattachSessionCoreAsync(ReattachSessionRequest request, CancellationToken cancellationToken)
    {
        sessions.TryGetSession(request.SessionId, out var oldSession);
        var oldConnectionId = oldSession?.AttachedClientConnectionId;

        replayCoordinator.BeginReplay(request.SessionId, Context.ConnectionId);

        var result = await sessions.ReattachSessionAsync(
            Context.UserIdentifier ?? "unknown",
            request,
            Context.ConnectionId,
            timeProvider.GetUtcNow(),
            cancellationToken);

        if (!result.IsSuccess)
        {
            replayCoordinator.AbortReplay(request.SessionId);
            return result;
        }

        if (!string.IsNullOrEmpty(oldConnectionId) && oldConnectionId != Context.ConnectionId)
        {
            _ = Clients.Client(oldConnectionId).SendAsync("SessionDisplaced",
                new SessionDisplacedEvent(request.SessionId), CancellationToken.None);
        }

        try
        {
            sessions.TryGetSession(request.SessionId, out var session);
            var workerConnectionId = session?.WorkerConnectionId;

            IReadOnlyList<TerminalChunk> snapshot = Array.Empty<TerminalChunk>();
            if (!string.IsNullOrEmpty(workerConnectionId))
            {
                try
                {
                    snapshot = await workerCommands.RequestScrollbackAsync(workerConnectionId, request.SessionId, cancellationToken);
                }
                catch (Exception ex)
                {
                    logger.LogWarning(ex, "RequestScrollback failed for session {SessionId}, sending empty replay.", request.SessionId);
                }
            }

            await Clients.Caller.SendAsync("SessionReattached", new SessionReattachedEvent(request.SessionId), cancellationToken);
            foreach (var chunk in snapshot)
            {
                await Clients.Caller.SendAsync("ReplayChunk", new ReplayChunk(chunk.SessionId, chunk.Stream, chunk.Payload), cancellationToken);
            }
            await Clients.Caller.SendAsync("ReplayCompleted", new ReplayCompleted(request.SessionId), cancellationToken);

            await replayCoordinator.FlushPendingAsync(
                request.SessionId,
                Context.ConnectionId,
                chunk => Clients.Caller.SendAsync("StdoutChunk", chunk, cancellationToken),
                cancellationToken);

            await sessions.MarkReplayCompleted(request.SessionId, Context.ConnectionId);
        }
        catch
        {
            replayCoordinator.AbortReplay(request.SessionId);
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
        if (!TerminalSizeLimits.IsValid(request.Columns, request.Rows))
        {
            throw new HubException("Invalid terminal size.");
        }

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
