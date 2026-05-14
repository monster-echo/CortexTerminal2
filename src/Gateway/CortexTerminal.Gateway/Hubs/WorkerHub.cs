using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Audit;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.WebSockets;
using CortexTerminal.Gateway.Workers;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging;
using System.Security.Claims;

namespace CortexTerminal.Gateway.Hubs;

[Authorize]
public sealed class WorkerHub(
    IWorkerRegistry workers,
    ISessionCoordinator sessions,
    IReplayCache replayCache,
    IAuditLogStore auditLog,
    IHubContext<TerminalHub> terminalHubContext,
    ILogger<WorkerHub> logger) : Hub
{
    private string GetUserId()
        => Context.User?.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? Context.User?.FindFirstValue(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)
            ?? Context.UserIdentifier
            ?? "unknown";

    public void RegisterWorker(string workerId)
    {
        var userId = GetUserId();
        workers.Register(workerId, Context.ConnectionId, ownerUserId: userId);
        var reboundSessionCount = sessions.RebindActiveSessions(userId, workerId, Context.ConnectionId);
        logger.LogInformation(
            "Worker {WorkerId} registered with connection {ConnectionId} by user {UserId}; rebound {SessionCount} active sessions.",
            workerId,
            Context.ConnectionId,
            userId,
            reboundSessionCount);
        auditLog.Record(new AuditLogEntry(
            Id: Guid.NewGuid().ToString("N"),
            Timestamp: DateTimeOffset.UtcNow,
            UserId: userId,
            UserName: userId,
            Action: "worker.connect",
            TargetEntity: "worker",
            TargetId: workerId
        ));
    }

    public void UpdateWorkerInfo(WorkerInfoFrame info)
    {
        var worker = workers.FindByConnectionId(Context.ConnectionId);
        if (worker is null)
        {
            logger.LogWarning("UpdateWorkerInfo from unknown connection {ConnectionId}.", Context.ConnectionId);
            return;
        }

        workers.UpdateMetadata(worker.WorkerId, new WorkerMetadata(
            info.Hostname,
            info.OperatingSystem,
            info.Architecture,
            info.MachineName,
            info.Version));
        logger.LogInformation("Worker {WorkerId} updated info: hostname={Hostname}, os={OS}, arch={Arch}, version={Version}.",
            worker.WorkerId, info.Hostname, info.OperatingSystem, info.Architecture, info.Version);
    }

    public override Task OnDisconnectedAsync(Exception? exception)
    {
        // Find and unregister the worker that belonged to this connection
        var worker = workers.FindByConnectionId(Context.ConnectionId);
        if (worker is not null)
        {
            workers.Unregister(worker.WorkerId);
            logger.LogInformation("Worker {WorkerId} disconnected (connection {ConnectionId}).", worker.WorkerId, Context.ConnectionId);
        }

        return base.OnDisconnectedAsync(exception);
    }

    public async Task ForwardStdout(TerminalChunk chunk)
    {
        logger.LogInformation("ForwardStdout: session={SessionId}, worker={ConnectionId}, {ByteCount} bytes.", chunk.SessionId, Context.ConnectionId, chunk.Payload.Length);

        if (!sessions.TryGetSession(chunk.SessionId, out var session))
        {
            logger.LogWarning("ForwardStdout DROP: session {SessionId} not found.", chunk.SessionId);
            return;
        }

        if (session.WorkerConnectionId != Context.ConnectionId)
        {
            logger.LogWarning("ForwardStdout DROP: session {SessionId} worker mismatch. Expected={Expected}, Actual={Actual}.", chunk.SessionId, session.WorkerConnectionId, Context.ConnectionId);
            return;
        }

        await replayCache.AppendAsync(new ReplayChunk(chunk.SessionId, chunk.Stream, chunk.Payload), Context.ConnectionAborted);

        if (!sessions.TryGetSession(chunk.SessionId, out session) ||
            session.WorkerConnectionId != Context.ConnectionId)
        {
            logger.LogWarning("ForwardStdout DROP: session {SessionId} changed after replay append.", chunk.SessionId);
            return;
        }

        if (session.AttachmentState != SessionAttachmentState.Attached)
        {
            logger.LogWarning("ForwardStdout DROP: session {SessionId} not attached. State={State}.", chunk.SessionId, session.AttachmentState);
            return;
        }

        if (session.AttachedClientConnectionId is null)
        {
            logger.LogWarning("ForwardStdout DROP: session {SessionId} has no attached client.", chunk.SessionId);
            return;
        }

        if (session.ReplayPending)
        {
            logger.LogWarning("ForwardStdout DROP: session {SessionId} replay pending.", chunk.SessionId);
            return;
        }

        await DeliverToClientAsync(session, "StdoutChunk", chunk, new WsOutputFrame { SessionId = chunk.SessionId, Stream = chunk.Stream, Payload = Convert.ToBase64String(chunk.Payload) });
        logger.LogDebug("ForwardStdout DELIVERED: session={SessionId} to client={ClientId}.", chunk.SessionId, session.AttachedClientConnectionId);
    }

    public async Task ForwardStderr(TerminalChunk chunk)
    {
        logger.LogDebug("ForwardStderr: session={SessionId}, worker={ConnectionId}, {ByteCount} bytes.", chunk.SessionId, Context.ConnectionId, chunk.Payload.Length);

        if (!sessions.TryGetSession(chunk.SessionId, out var session))
        {
            logger.LogWarning("ForwardStderr DROP: session {SessionId} not found.", chunk.SessionId);
            return;
        }

        if (session.WorkerConnectionId != Context.ConnectionId)
        {
            logger.LogWarning("ForwardStderr DROP: session {SessionId} worker mismatch. Expected={Expected}, Actual={Actual}.", chunk.SessionId, session.WorkerConnectionId, Context.ConnectionId);
            return;
        }

        await replayCache.AppendAsync(new ReplayChunk(chunk.SessionId, chunk.Stream, chunk.Payload), Context.ConnectionAborted);

        if (!sessions.TryGetSession(chunk.SessionId, out session) ||
            session.WorkerConnectionId != Context.ConnectionId)
        {
            logger.LogWarning("ForwardStderr DROP: session {SessionId} changed after replay append.", chunk.SessionId);
            return;
        }

        if (session.AttachmentState != SessionAttachmentState.Attached)
        {
            logger.LogWarning("ForwardStderr DROP: session {SessionId} not attached. State={State}.", chunk.SessionId, session.AttachmentState);
            return;
        }

        if (session.AttachedClientConnectionId is null)
        {
            logger.LogWarning("ForwardStderr DROP: session {SessionId} has no attached client.", chunk.SessionId);
            return;
        }

        if (session.ReplayPending)
        {
            logger.LogWarning("ForwardStderr DROP: session {SessionId} replay pending.", chunk.SessionId);
            return;
        }

        await DeliverToClientAsync(session, "StderrChunk", chunk, new WsOutputFrame { SessionId = chunk.SessionId, Stream = chunk.Stream, Payload = Convert.ToBase64String(chunk.Payload) });
        logger.LogDebug("ForwardStderr DELIVERED: session={SessionId} to client={ClientId}.", chunk.SessionId, session.AttachedClientConnectionId);
    }

    public async Task ForwardLatencyProbe(LatencyProbeFrame frame)
    {
        logger.LogDebug("ForwardLatencyProbe: session={SessionId}, probe={ProbeId}, worker={ConnectionId}.", frame.SessionId, frame.ProbeId, Context.ConnectionId);

        if (!sessions.TryGetSession(frame.SessionId, out var session))
        {
            logger.LogWarning("ForwardLatencyProbe DROP: session {SessionId} not found.", frame.SessionId);
            return;
        }

        if (session.WorkerConnectionId != Context.ConnectionId)
        {
            logger.LogWarning("ForwardLatencyProbe DROP: session {SessionId} worker mismatch. Expected={Expected}, Actual={Actual}.", frame.SessionId, session.WorkerConnectionId, Context.ConnectionId);
            return;
        }

        if (session.AttachmentState != SessionAttachmentState.Attached)
        {
            logger.LogWarning("ForwardLatencyProbe DROP: session {SessionId} not attached. State={State}.", frame.SessionId, session.AttachmentState);
            return;
        }

        if (session.AttachedClientConnectionId is null)
        {
            logger.LogWarning("ForwardLatencyProbe DROP: session {SessionId} has no attached client.", frame.SessionId);
            return;
        }

        await DeliverToClientAsync(session, "LatencyProbeAck", frame, new WsLatencyAckFrame { ProbeId = frame.ProbeId, ClientTime = 0, ServerTime = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() });
        logger.LogDebug("ForwardLatencyProbe DELIVERED: session={SessionId} probe={ProbeId} to client={ClientId}.", frame.SessionId, frame.ProbeId, session.AttachedClientConnectionId);
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
            await DeliverToClientAsync(session, "SessionStartFailed", evt, new WsErrorFrame { SessionId = evt.SessionId, Code = "session-start-failed", Message = evt.Reason });
        }
    }

    public async Task SessionExited(SessionExited evt)
    {
        if (!sessions.TryGetSession(evt.SessionId, out var session) || session.WorkerConnectionId != Context.ConnectionId)
        {
            return;
        }

        var attachedClientConnectionId = session.AttachedClientConnectionId;
        replayCache.Clear(evt.SessionId);
        sessions.RemoveSession(evt.SessionId);

        if (attachedClientConnectionId is not null)
        {
            await DeliverToClientAsync(session, "SessionExited", evt, new WsExitedFrame { SessionId = evt.SessionId, ExitCode = evt.ExitCode, Reason = evt.Reason });
        }
    }

    /// <summary>
    /// Deliver a message to the attached client. Checks if the connection is a native WebSocket
    /// (connection ID starts with "ws-") and routes accordingly.
    /// </summary>
    private async Task DeliverToClientAsync(SessionRecord session, string signalRMethod, object signalRPayload, object wsFrame)
    {
        var clientId = session.AttachedClientConnectionId;
        if (clientId is null) return;

        if (clientId.StartsWith("ws-", StringComparison.Ordinal))
        {
            await TerminalWebSocketConnectionRegistry.SendToSessionAsync(session.SessionId, wsFrame, Context.ConnectionAborted);
        }
        else
        {
            await terminalHubContext.Clients.Client(clientId).SendAsync(signalRMethod, signalRPayload);
        }
    }
}
