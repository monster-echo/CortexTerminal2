using System.Collections.Concurrent;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Workers;

namespace CortexTerminal.Gateway.Sessions;

public sealed class InMemorySessionCoordinator(IWorkerRegistry workers) : ISessionCoordinator
{
    private readonly ConcurrentDictionary<string, SessionRecord> _sessions = new();

    public Task<CreateSessionResult> CreateSessionAsync(string userId, CreateSessionRequest request, CancellationToken cancellationToken)
    {
        if (!workers.TryGetLeastBusy(out var worker))
        {
            return Task.FromResult(CreateSessionResult.Failure("no-worker-available"));
        }

        var sessionId = $"sess_{Guid.NewGuid():N}";
        var record = new SessionRecord(sessionId, userId, worker.WorkerId, worker.ConnectionId, request.Columns, request.Rows);
        _sessions[sessionId] = record;
        return Task.FromResult(CreateSessionResult.Success(new CreateSessionResponse(sessionId, worker.WorkerId)));
    }

    public bool TryGetSession(string sessionId, out SessionRecord session)
        => _sessions.TryGetValue(sessionId, out session!);
}
