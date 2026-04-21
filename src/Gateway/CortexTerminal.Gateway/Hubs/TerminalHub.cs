using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Sessions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace CortexTerminal.Gateway.Hubs;

[Authorize]
public sealed class TerminalHub(
    ISessionCoordinator sessions,
    IReplayCache replayCache,
    TimeProvider timeProvider) : Hub
{
    public Task<CreateSessionResult> CreateSession(CreateSessionRequest request, CancellationToken cancellationToken)
        => sessions.CreateSessionAsync(Context.UserIdentifier ?? "unknown", request, cancellationToken);

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

        await Clients.Caller.SendAsync("SessionReattached", new SessionReattachedEvent(request.SessionId), cancellationToken);
        foreach (var chunk in replayCache.GetSnapshot(request.SessionId))
        {
            await Clients.Caller.SendAsync("ReplayChunk", chunk, cancellationToken);
        }
        await Clients.Caller.SendAsync("ReplayCompleted", new ReplayCompleted(request.SessionId), cancellationToken);
        return result;
    }

    public async Task WriteInput(WriteInputFrame frame)
    {
        if (!sessions.TryGetSession(frame.SessionId, out var session))
        {
            throw new HubException("Unknown session.");
        }

        await Clients.Client(session.WorkerConnectionId).SendAsync("WriteInput", frame);
    }
}
