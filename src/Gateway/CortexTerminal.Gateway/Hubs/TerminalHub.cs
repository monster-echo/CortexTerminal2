using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Sessions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace CortexTerminal.Gateway.Hubs;

[Authorize]
public sealed class TerminalHub(ISessionCoordinator sessions) : Hub
{
    public Task<CreateSessionResult> CreateSession(CreateSessionRequest request, CancellationToken cancellationToken)
        => sessions.CreateSessionAsync(Context.UserIdentifier ?? "unknown", request, cancellationToken);

    public async Task WriteInput(WriteInputFrame frame)
    {
        if (!sessions.TryGetSession(frame.SessionId, out var session))
        {
            throw new HubException("Unknown session.");
        }

        await Clients.Client(session.WorkerConnectionId).SendAsync("WriteInput", frame);
    }
}
