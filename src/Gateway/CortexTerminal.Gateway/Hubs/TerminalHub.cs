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
    IWorkerRegistry workers,
    ScrollbackSettings scrollbackSettings,
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

    /// <summary>
    /// Session outlives the terminal: when the coordinator reports the shell is
    /// gone (Expired/Exited after a worker restart or start failure), start a
    /// fresh shell for the SAME session id — Windows-Terminal restart-shell
    /// semantics. The device-side worker snapshot supplies prior history; the
    /// fresh shell's output appends below the reconnect divider.
    /// </summary>
    private async Task RestartShellIfRequiredAsync(ReattachSessionResult result, string sessionId, CancellationToken cancellationToken)
    {
        if (!result.ShellRestartRequired)
        {
            return;
        }
        if (!sessions.TryGetSession(sessionId, out var session)
            || !workers.TryGetWorker(session.WorkerId, out var worker))
        {
            throw new HubException("worker-offline");
        }
        // The session's recorded connection died with the old worker process —
        // rebind to the worker's current connection before dispatching.
        sessions.TryRebindSessionWorkerConnection(sessionId, worker.ConnectionId);
        await workerCommands.StartSessionAsync(
            worker.ConnectionId,
            new StartSessionCommand(sessionId, session.Columns, session.Rows, scrollbackSettings.MaxBytes, null),
            cancellationToken);
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
        await sessions.DetachSessionAsync(Context.UserIdentifier ?? "unknown", sessionId, now, cancellationToken, clientConnectionId: Context.ConnectionId);
        await Clients.Caller.SendAsync("SessionDetached", new SessionDetachedEvent(sessionId), cancellationToken);
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

        try
        {
            await RestartShellIfRequiredAsync(result, request.SessionId, cancellationToken);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Shell restart failed for session {SessionId}.", request.SessionId);
            replayCoordinator.AbortReplay(request.SessionId);
            return ReattachSessionResult.Failure("worker-offline");
        }

        if (!string.IsNullOrEmpty(oldConnectionId) && oldConnectionId != Context.ConnectionId)
        {
            if (oldConnectionId.StartsWith("ws-", StringComparison.Ordinal))
            {
                // 旧附着是原生 WS 连接（如 Flutter 客户端）：能力协商下发 displaced 帧并关闭。
                _ = WebSockets.DisplacedNotifier.NotifyWebSocketAsync(request.SessionId, oldConnectionId, logger);
            }
            else
            {
                _ = Clients.Client(oldConnectionId).SendAsync("SessionDisplaced",
                    new SessionDisplacedEvent(request.SessionId), CancellationToken.None);
            }
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
            await sessions.DetachSessionAsync(Context.UserIdentifier ?? "unknown", request.SessionId, timeProvider.GetUtcNow(), cancellationToken, clientConnectionId: Context.ConnectionId);
            throw;
        }

        return result;
    }

    /// <summary>
    /// Incremental reattach for cache-capable clients: the caller declares the
    /// newest scrollback sequence it already holds and receives only the chunks
    /// after it (ReplayDelta* events) — the screen continues its cached stream
    /// without a reset. Falls back to the legacy full-replay event sequence
    /// (SessionReattached → ReplayChunk* → ReplayCompleted) when the worker
    /// lacks the incremental RPC or the cursor predates the retained window, so
    /// clients reuse their existing full-replay handling. Legacy clients never
    /// call this method and never see the delta events.
    /// </summary>
    public async Task<ReattachSessionResult> ReattachSessionIncremental(
        ReattachSessionSinceRequest request, CancellationToken cancellationToken)
    {
        sessions.TryGetSession(request.SessionId, out var oldSession);
        var oldConnectionId = oldSession?.AttachedClientConnectionId;

        replayCoordinator.BeginReplay(request.SessionId, Context.ConnectionId);

        var result = await sessions.ReattachSessionAsync(
            Context.UserIdentifier ?? "unknown",
            new ReattachSessionRequest(request.SessionId),
            Context.ConnectionId,
            timeProvider.GetUtcNow(),
            cancellationToken);

        if (!result.IsSuccess)
        {
            replayCoordinator.AbortReplay(request.SessionId);
            return result;
        }

        try
        {
            await RestartShellIfRequiredAsync(result, request.SessionId, cancellationToken);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Shell restart failed for session {SessionId}.", request.SessionId);
            replayCoordinator.AbortReplay(request.SessionId);
            return ReattachSessionResult.Failure("worker-offline");
        }

        if (!string.IsNullOrEmpty(oldConnectionId) && oldConnectionId != Context.ConnectionId)
        {
            if (oldConnectionId.StartsWith("ws-", StringComparison.Ordinal))
            {
                _ = WebSockets.DisplacedNotifier.NotifyWebSocketAsync(request.SessionId, oldConnectionId, logger);
            }
            else
            {
                _ = Clients.Client(oldConnectionId).SendAsync("SessionDisplaced",
                    new SessionDisplacedEvent(request.SessionId), CancellationToken.None);
            }
        }

        try
        {
            sessions.TryGetSession(request.SessionId, out var session);
            var workerConnectionId = session?.WorkerConnectionId;

            ScrollbackDelta? delta = null;
            IReadOnlyList<TerminalChunk> snapshot = Array.Empty<TerminalChunk>();
            if (!string.IsNullOrEmpty(workerConnectionId))
            {
                try
                {
                    delta = await workerCommands.RequestScrollbackSinceAsync(
                        workerConnectionId, request.SessionId, request.SinceSeq, cancellationToken);
                }
                catch (Exception ex)
                {
                    logger.LogWarning(ex, "RequestScrollbackSince failed for session {SessionId}; falling back to legacy full replay.", request.SessionId);
                }
                if (delta is null)
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
            }

            if (delta is not null && !delta.Gap)
            {
                // Incremental: the client continues its cached stream — no reset.
                await Clients.Caller.SendAsync("ReplayDeltaStarted", new ReplayDeltaStarted(request.SessionId), cancellationToken);
                foreach (var item in delta.Items)
                {
                    await Clients.Caller.SendAsync("ReplayDeltaChunk", new ReplayDeltaChunk(item.Chunk.SessionId, item.Chunk.Stream, item.Chunk.Payload, item.Seq), cancellationToken);
                }
                await Clients.Caller.SendAsync("ReplayDeltaCompleted", new ReplayDeltaCompleted(request.SessionId, delta.LastSeq), cancellationToken);
            }
            else
            {
                // Gap (or an old worker): send the full retained buffer over the
                // legacy event sequence — the client resets and swaps exactly
                // like a normal full replay.
                var resetSnapshot = delta?.Items.Select(i => i.Chunk).ToArray() ?? snapshot;
                await Clients.Caller.SendAsync("SessionReattached", new SessionReattachedEvent(request.SessionId), cancellationToken);
                foreach (var chunk in resetSnapshot)
                {
                    await Clients.Caller.SendAsync("ReplayChunk", new ReplayChunk(chunk.SessionId, chunk.Stream, chunk.Payload), cancellationToken);
                }
                await Clients.Caller.SendAsync("ReplayCompleted", new ReplayCompleted(request.SessionId), cancellationToken);
            }

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
            await sessions.DetachSessionAsync(Context.UserIdentifier ?? "unknown", request.SessionId, timeProvider.GetUtcNow(), cancellationToken, clientConnectionId: Context.ConnectionId);
            throw;
        }

        return result;
    }

    public async Task WriteInput(WriteInputFrame frame)
    {
        var session = RequireOwnedSession(frame.SessionId);
        logger.LogInformation(
            "WriteInput: session={SessionId} user={UserId} client={ClientId} {ByteCount}B",
            frame.SessionId,
            Context.UserIdentifier,
            Context.ConnectionId,
            frame.Payload?.Length ?? 0);
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
