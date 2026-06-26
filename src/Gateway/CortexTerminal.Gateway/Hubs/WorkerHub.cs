using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Audit;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Stats;
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
    ReplayCoordinator replayCoordinator,
    IAuditLogStore auditLog,
    IHubContext<TerminalHub> terminalHubContext,
    IGatewayStatsService stats,
    ISessionStatsService sessionStats,
    ArtifactService artifacts,
    AgentActivityService agentActivity,
    ILogger<WorkerHub> logger) : Hub
{
    private string GetUserId()
        => Context.User?.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? Context.User?.FindFirstValue(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)
            ?? Context.UserIdentifier
            ?? "unknown";

    public async Task RegisterWorker(string workerId)
    {
        var userId = GetUserId();
        workers.Register(workerId, Context.ConnectionId, ownerUserId: userId);
        var reboundSessionCount = await sessions.RebindActiveSessions(userId, workerId, Context.ConnectionId);
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

        workers.PersistMetadata(worker.WorkerId, new WorkerMetadata(
            info.Hostname,
            info.OperatingSystem,
            info.Architecture,
            info.MachineName,
            info.Version));
        workers.UpdateMetrics(worker.WorkerId, new WorkerMetrics(
            info.CpuUsagePercent,
            info.MemoryUsagePercent));
        logger.LogInformation("Worker {WorkerId} updated info: hostname={Hostname}, os={OS}, arch={Arch}, version={Version}, cpu={Cpu}%, mem={Mem}%.",
            worker.WorkerId, info.Hostname, info.OperatingSystem, info.Architecture, info.Version,
            info.CpuUsagePercent, info.MemoryUsagePercent);
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        // Find and unregister the worker that belonged to this connection
        var worker = workers.FindByConnectionId(Context.ConnectionId);
        if (worker is not null)
        {
            var workerId = worker.WorkerId;
            var connectionId = Context.ConnectionId;

            workers.Unregister(workerId);
            logger.LogInformation("Worker {WorkerId} disconnected (connection {ConnectionId}).", workerId, connectionId);

            // Move sessions to Recovering instead of expiring them outright.
            // This gives the worker (or a gateway restart) a 60s window to reconnect via
            // DetachedSessionExpiryService. Without this, a graceful gateway shutdown
            // would expire all sessions in DB and nothing could be recovered.
            var transitionedSessions = await sessions.TransitionToRecovering(workerId, connectionId);
            if (transitionedSessions.Count > 0)
            {
                logger.LogInformation(
                    "Transitioned {SessionCount} sessions to Recovering for disconnected worker {WorkerId} (connection {ConnectionId}).",
                    transitionedSessions.Count, workerId, connectionId);

                foreach (var session in transitionedSessions)
                {
                    replayCoordinator.AbortReplay(session.SessionId);
                }
            }
        }

        await base.OnDisconnectedAsync(exception);
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

        sessions.TouchSessionActivity(chunk.SessionId, DateTimeOffset.UtcNow);
        stats.RecordBytesTransferred(chunk.Payload.Length);
        sessionStats.RecordBytes(chunk.SessionId, session.UserId, chunk.Payload.Length);

        if (session.ReplayPending && replayCoordinator.TryEnqueue(chunk.SessionId, chunk))
        {
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

        stats.RecordBytesTransferred(chunk.Payload.Length);
        sessionStats.RecordBytes(chunk.SessionId, session.UserId, chunk.Payload.Length);

        if (session.ReplayPending && replayCoordinator.TryEnqueue(chunk.SessionId, chunk))
        {
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

        await sessions.MarkSessionStartFailed(evt.SessionId, evt.Reason);
        replayCoordinator.AbortReplay(evt.SessionId);

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
        replayCoordinator.AbortReplay(evt.SessionId);
        await sessions.RemoveSession(evt.SessionId);

        if (attachedClientConnectionId is not null)
        {
            await DeliverToClientAsync(session, "SessionExited", evt, new WsExitedFrame { SessionId = evt.SessionId, ExitCode = evt.ExitCode, Reason = evt.Reason });
        }
    }

    /// <summary>
    /// Worker-side: an AI agent (Claude Code / Codex / OpenCode) has started inside this session.
    /// Persist the activity event, record agent kind + agent session id on the session row, and
    /// fan out to every Console / WebSocket client owned by the user so the session list and the
    /// agent activity timeline update in real time.
    /// </summary>
    public async Task ForwardAgentStarted(AgentStartedFrame frame)
    {
        logger.LogInformation("ForwardAgentStarted: session={SessionId}, kind={Kind}, agent={AgentSessionId}.", frame.SessionId, frame.Kind, frame.AgentSessionId);
        await agentActivity.HandleStartedAsync(frame.SessionId, Context.ConnectionId, frame, Context.ConnectionAborted);
    }

    public async Task ForwardAgentPromptSubmitted(AgentPromptSubmittedFrame frame)
    {
        logger.LogDebug("ForwardAgentPromptSubmitted: session={SessionId}, promptLen={Length}.", frame.SessionId, frame.PromptText?.Length ?? 0);
        await agentActivity.HandlePromptSubmittedAsync(frame.SessionId, Context.ConnectionId, frame, Context.ConnectionAborted);
    }

    public async Task ForwardAgentToolCall(AgentToolCallFrame frame)
    {
        logger.LogDebug("ForwardAgentToolCall: session={SessionId}, tool={Tool}, isError={IsError}.", frame.SessionId, frame.ToolName, frame.IsError);
        await agentActivity.HandleToolCallAsync(frame.SessionId, Context.ConnectionId, frame, Context.ConnectionAborted);
    }

    public async Task ForwardAgentStopped(AgentStoppedFrame frame)
    {
        logger.LogInformation("ForwardAgentStopped: session={SessionId}, cost=${Cost}.", frame.SessionId, frame.TotalCostUsd);
        await agentActivity.HandleStoppedAsync(frame.SessionId, Context.ConnectionId, frame, Context.ConnectionAborted);
    }

    /// <summary>
    /// Worker-side RPC: apply for a presigned PUT URL so the worker can upload a file its
    /// FileSystemWatcher detected to S3 without ever holding S3 credentials. Gateway creates
    /// a Pending artifact row and returns the URL + artifactId. The worker follows up with
    /// <see cref="CompleteArtifactUpload"/>.
    /// </summary>
    public async Task<UploadUrlResponse> RequestArtifactUploadUrl(CreateArtifactRequest request)
    {
        var worker = workers.FindByConnectionId(Context.ConnectionId)
            ?? throw new HubException("Worker not registered");
        if (string.IsNullOrEmpty(worker.OwnerUserId)) throw new HubException("Worker has no owner");
        return await artifacts.CreateForWorkerUploadAsync(Context.ConnectionId, worker.OwnerUserId!, request, Context.ConnectionAborted);
    }

    /// <summary>
    /// Worker-side RPC: report that an artifact has been fully PUT to S3. Gateway HEADs the
    /// object to verify, flips status to Ready, fans out ArtifactChanged(created), and pushes
    /// the new artifact to every Console/WS connection owned by the user.
    /// </summary>
    public async Task<CompleteArtifactAck> CompleteArtifactUpload(CompleteArtifactRequest request)
    {
        var worker = workers.FindByConnectionId(Context.ConnectionId)
            ?? throw new HubException("Worker not registered");
        if (string.IsNullOrEmpty(worker.OwnerUserId)) throw new HubException("Worker has no owner");
        try
        {
            await artifacts.CompleteWorkerUploadAsync(Context.ConnectionId, worker.OwnerUserId!, request.ArtifactId, request.ContentSha256, Context.ConnectionAborted);
            return new CompleteArtifactAck(Success: true, Error: null);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "CompleteArtifactUpload failed for {ArtifactId}.", request.ArtifactId);
            return new CompleteArtifactAck(Success: false, Error: ex.Message);
        }
    }

    /// <summary>
    /// Worker-side RPC: the worker's FileSystemWatcher noticed the local mirror was modified or
    /// deleted out-of-band (e.g. user/agent rewrote or removed the file). Gateway propagates the
    /// change so the Console side stays in sync. Currently we treat this as a hint and re-route
    /// through the upload pipeline; deletion events mark the row Deleted and broadcast.
    /// </summary>
    public async Task ReportArtifactDeleted(ReportArtifactDeletedFrame frame)
    {
        var worker = workers.FindByConnectionId(Context.ConnectionId);
        if (worker is null) return;
        if (!sessions.TryGetSession(frame.SessionId, out var session) || session.WorkerConnectionId != Context.ConnectionId) return;
        await artifacts.DeleteByWorkerAsync(frame.SessionId, frame.Filename, Context.ConnectionAborted);
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
