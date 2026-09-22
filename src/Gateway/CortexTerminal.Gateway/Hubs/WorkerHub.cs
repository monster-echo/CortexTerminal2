using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Audit;
using CortexTerminal.Gateway.Membership;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Stats;
using CortexTerminal.Gateway.WebSockets;
using CortexTerminal.Gateway.Workers;
using CortexTerminal.Gateway.Workspaces;
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
    WorkspaceRegistry workspaceRegistry,
    RelayOptions relayOptions,
    AgentActivityService agentActivity,
    IEntitlementService entitlements,
    ILogger<WorkerHub> logger) : Hub
{
    private readonly RelayOptions _relayOptions = relayOptions;

    private string GetUserId()
        => Context.User?.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? Context.User?.FindFirstValue(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)
            ?? Context.UserIdentifier
            ?? "unknown";

    public async Task RegisterWorker(string workerId)
    {
        var userId = GetUserId();
        // Enforce plan quota BEFORE registering — authoritative source is the registry's in-memory
        // live-worker set (DB write is fire-and-forget). Throws MembershipQuotaExceededException
        // (an InvalidOperationException); SignalR surfaces it to the client as a HubException.
        await entitlements.EnforceWorkerQuotaAsync(userId, Context.ConnectionAborted);
        workers.Register(workerId, Context.ConnectionId, ownerUserId: userId);
        var reboundSessionCount = await sessions.RebindActiveSessions(userId, workerId, Context.ConnectionId);

        // 签发 Relay worker 令牌（24h），经可信通道推给 Worker，供其连入 Relay 持久数据面 WS。
        if (!string.IsNullOrEmpty(_relayOptions.SharedSecret))
        {
            var relayToken = RelayToken.Mint(
                _relayOptions.SharedSecret,
                RelayToken.AudienceWorkerRelay,
                workerId,
                DateTimeOffset.UtcNow.AddHours(24));
            try
            {
                await Clients.Caller.InvokeAsync<FileOperationAck>(
                    "IssueRelayToken", _relayOptions.PublicUrl, relayToken, Context.ConnectionAborted);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to push relay token to worker {WorkerId}.", workerId);
            }
        }

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

    public async Task UpdateWorkerInfo(WorkerInfoFrame info)
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

        // 端点协商：记录 Worker 的 LAN 直连与公网直连传输端点（文件传输优先直连、Relay 兜底）
        workers.UpdateTransferEndpoints(
            worker.WorkerId,
            info.LanEndpoints ?? Array.Empty<string>(),
            info.PublicTransferBaseUrl);

        // Worker 首次上报 home 时幂等创建默认工作区（后续上报同 worker 已有工作区则跳过）
        if (!string.IsNullOrEmpty(info.HomePath) && !string.IsNullOrEmpty(worker.OwnerUserId))
        {
            try
            {
                await workspaceRegistry.EnsureDefaultAsync(worker.OwnerUserId!, worker.WorkerId, info.HomePath!);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to ensure default workspace for worker {WorkerId}.", worker.WorkerId);
            }
        }

        logger.LogInformation("Worker {WorkerId} updated info: hostname={Hostname}, os={OS}, arch={Arch}, version={Version}, cpu={Cpu}%, mem={Mem}%.",
            worker.WorkerId, info.Hostname, info.OperatingSystem, info.Architecture, info.Version,
            info.CpuUsagePercent, info.MemoryUsagePercent);
    }

    public async Task ReportWorkerSessions(WorkerSessionsSnapshot snapshot)
    {
        var userId = GetUserId();
        var worker = workers.FindByConnectionId(Context.ConnectionId);
        if (worker is null)
        {
            logger.LogWarning("ReportWorkerSessions from unknown connection {ConnectionId}.", Context.ConnectionId);
            return;
        }

        var live = snapshot.LiveSessionIds is null
            ? new HashSet<string>(StringComparer.Ordinal)
            : new HashSet<string>(snapshot.LiveSessionIds, StringComparer.Ordinal);

        var expired = await sessions.ReconcileWorkerSessionsAsync(userId, worker.WorkerId, live);
        logger.LogInformation(
            "Worker {WorkerId} reported {Live} live sessions; expired {Expired} ghosts.",
            worker.WorkerId,
            live.Count,
            expired.Count);
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

            // Mark the worker's sessions Recovering (worker link is down). There is NO timer
            // reaping them — a session stays Recovering until this worker reconnects and
            // RebindActiveSessions rebounds it (or ReportWorkerSessions reconciles it). PTY
            // liveness is the worker's call to make, not the gateway's.
            var transitionedSessions = await sessions.TransitionToRecovering(workerId, connectionId);
            if (transitionedSessions.Count > 0)
            {
                logger.LogInformation(
                    "Transitioned {SessionCount} sessions to Recovering for disconnected worker {WorkerId} (connection {ConnectionId}).",
                    transitionedSessions.Count, workerId, connectionId);

                foreach (var session in transitionedSessions)
                {
                    replayCoordinator.AbortReplay(session.SessionId);
                    // 通知附着在该 session 上的终端客户端：worker 链路已断。
                    // 之前只改库不推送，客户端（客户端 WS 到网关仍活着）会一直显示
                    // 「已连接」的死链。客户端收到后进入 reconnecting 退避重连。
                    _ = TerminalWebSocketConnectionRegistry.SendToSessionAsync(
                        session.SessionId,
                        new { type = "error", code = "worker-offline", sessionId = session.SessionId, message = "Worker link is down." },
                        CancellationToken.None);
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

    public async Task ForwardAgentSessionEnded(AgentSessionEndedFrame frame)
    {
        logger.LogDebug("ForwardAgentSessionEnded: session={SessionId}, reason={Reason}.", frame.SessionId, frame.Reason);
        await agentActivity.HandleSessionEndedAsync(frame.SessionId, Context.ConnectionId, frame, Context.ConnectionAborted);
    }

    public async Task ForwardAgentSubagentStopped(AgentSubagentStoppedFrame frame)
    {
        logger.LogDebug("ForwardAgentSubagentStopped: session={SessionId}, subagent={SubagentId}.", frame.SessionId, frame.SubagentId);
        await agentActivity.HandleSubagentStoppedAsync(frame.SessionId, Context.ConnectionId, frame, Context.ConnectionAborted);
    }

    public async Task ForwardAgentNotified(AgentNotifiedFrame frame)
    {
        logger.LogDebug("ForwardAgentNotified: session={SessionId}, title={Title}.", frame.SessionId, frame.Title);
        await agentActivity.HandleNotifiedAsync(frame.SessionId, Context.ConnectionId, frame, Context.ConnectionAborted);
    }

    public async Task ForwardAgentCompacting(AgentCompactingFrame frame)
    {
        logger.LogDebug("ForwardAgentCompacting: session={SessionId}, trigger={Trigger}.", frame.SessionId, frame.Trigger);
        await agentActivity.HandleCompactingAsync(frame.SessionId, Context.ConnectionId, frame, Context.ConnectionAborted);
    }

    public async Task ForwardAgentTitleUpdated(AgentTitleUpdatedFrame frame)
    {
        logger.LogInformation("ForwardAgentTitleUpdated: session={SessionId}, title={Title}.", frame.SessionId, frame.Title);
        await agentActivity.HandleTitleUpdatedAsync(frame.SessionId, Context.ConnectionId, frame, Context.ConnectionAborted);
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
