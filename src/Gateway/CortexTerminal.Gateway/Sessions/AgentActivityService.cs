using System.Text.Json;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Hubs;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Gateway.Sessions;

/// <summary>
/// Persists agent activity events, mutates session metadata (agent kind, agent session id,
/// inferred title on first prompt), and fans out the structured frame to every Console /
/// WebSocket client owned by the session's user.
/// </summary>
public sealed class AgentActivityService
{
    private static readonly HashSet<string> TrackedEventTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "AgentStarted",
        "AgentPromptSubmitted",
        "AgentToolCall",
        "AgentStopped",
        "AgentSessionEnded",
        "AgentSubagentStopped",
        "AgentNotified",
        "AgentCompacting",
    };

    private const int InferredTitleMaxLength = 200;
    private const int InferredTitleSourceMaxLength = 100;

    private readonly IDbContextFactory<AppDbContext> _dbFactory;
    private readonly IHubContext<TerminalHub> _terminalHub;
    private readonly ILogger<AgentActivityService> _logger;

    public AgentActivityService(
        IDbContextFactory<AppDbContext> dbFactory,
        IHubContext<TerminalHub> terminalHub,
        ILogger<AgentActivityService> logger)
    {
        _dbFactory = dbFactory;
        _terminalHub = terminalHub;
        _logger = logger;
    }

    public async Task HandleStartedAsync(string sessionId, string workerConnectionId, AgentStartedFrame frame, CancellationToken cancellationToken)
    {
        if (!await EnsureWorkerOwnsSessionAsync(sessionId, workerConnectionId, cancellationToken)) return;

        await PersistEventAsync(sessionId, "AgentStarted", frame, cancellationToken);

        var kindName = AgentKindNames.ToName(frame.Kind);
        await using var db = await _dbFactory.CreateDbContextAsync(cancellationToken);
        var entity = await db.Sessions.FindAsync(new object?[] { sessionId }, cancellationToken);
        if (entity is null)
        {
            _logger.LogWarning("AgentStarted for unknown session {SessionId}.", sessionId);
            return;
        }
        entity.AgentKind = kindName;
        entity.AgentSessionId = frame.AgentSessionId;
        entity.LastActivityAtUtc = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(cancellationToken);

        await BroadcastAsync(entity.UserId, "AgentStarted", frame, cancellationToken);
    }

    public async Task HandlePromptSubmittedAsync(string sessionId, string workerConnectionId, AgentPromptSubmittedFrame frame, CancellationToken cancellationToken)
    {
        if (!await EnsureWorkerOwnsSessionAsync(sessionId, workerConnectionId, cancellationToken)) return;

        await PersistEventAsync(sessionId, "AgentPromptSubmitted", frame, cancellationToken);

        await using var db = await _dbFactory.CreateDbContextAsync(cancellationToken);
        var entity = await db.Sessions.FindAsync(new object?[] { sessionId }, cancellationToken);
        if (entity is null)
        {
            _logger.LogWarning("AgentPromptSubmitted for unknown session {SessionId}.", sessionId);
            return;
        }
        entity.LastActivityAtUtc = DateTimeOffset.UtcNow;

        if (string.IsNullOrEmpty(entity.InferredTitle) && !string.IsNullOrWhiteSpace(frame.PromptText))
        {
            var source = frame.PromptText.Trim();
            if (source.Length > InferredTitleSourceMaxLength) source = source[..InferredTitleSourceMaxLength] + "…";
            entity.InferredTitle = source.Length > InferredTitleMaxLength ? source[..InferredTitleMaxLength] : source;
        }

        await db.SaveChangesAsync(cancellationToken);

        await BroadcastAsync(entity.UserId, "AgentPromptSubmitted", frame, cancellationToken);
    }

    public async Task HandleToolCallAsync(string sessionId, string workerConnectionId, AgentToolCallFrame frame, CancellationToken cancellationToken)
    {
        if (!await EnsureWorkerOwnsSessionAsync(sessionId, workerConnectionId, cancellationToken)) return;

        await PersistEventAsync(sessionId, "AgentToolCall", frame, cancellationToken);

        await using var db = await _dbFactory.CreateDbContextAsync(cancellationToken);
        var entity = await db.Sessions.FindAsync(new object?[] { sessionId }, cancellationToken);
        if (entity is null)
        {
            _logger.LogWarning("AgentToolCall for unknown session {SessionId}.", sessionId);
            return;
        }
        entity.LastActivityAtUtc = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(cancellationToken);

        await BroadcastAsync(entity.UserId, "AgentToolCall", frame, cancellationToken);
    }

    public async Task HandleStoppedAsync(string sessionId, string workerConnectionId, AgentStoppedFrame frame, CancellationToken cancellationToken)
    {
        if (!await EnsureWorkerOwnsSessionAsync(sessionId, workerConnectionId, cancellationToken)) return;

        await PersistEventAsync(sessionId, "AgentStopped", frame, cancellationToken);

        await using var db = await _dbFactory.CreateDbContextAsync(cancellationToken);
        var entity = await db.Sessions.FindAsync(new object?[] { sessionId }, cancellationToken);
        if (entity is null)
        {
            _logger.LogWarning("AgentStopped for unknown session {SessionId}.", sessionId);
            return;
        }
        entity.LastActivityAtUtc = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(cancellationToken);

        await BroadcastAsync(entity.UserId, "AgentStopped", frame, cancellationToken);
    }

    public async Task HandleSessionEndedAsync(string sessionId, string workerConnectionId, AgentSessionEndedFrame frame, CancellationToken cancellationToken)
    {
        if (!await EnsureWorkerOwnsSessionAsync(sessionId, workerConnectionId, cancellationToken)) return;

        await PersistEventAsync(sessionId, "AgentSessionEnded", frame, cancellationToken);

        await using var db = await _dbFactory.CreateDbContextAsync(cancellationToken);
        var entity = await db.Sessions.FindAsync(new object?[] { sessionId }, cancellationToken);
        if (entity is null)
        {
            _logger.LogWarning("AgentSessionEnded for unknown session {SessionId}.", sessionId);
            return;
        }
        entity.LastActivityAtUtc = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(cancellationToken);

        await BroadcastAsync(entity.UserId, "AgentSessionEnded", frame, cancellationToken);
    }

    public async Task HandleSubagentStoppedAsync(string sessionId, string workerConnectionId, AgentSubagentStoppedFrame frame, CancellationToken cancellationToken)
    {
        if (!await EnsureWorkerOwnsSessionAsync(sessionId, workerConnectionId, cancellationToken)) return;

        await PersistEventAsync(sessionId, "AgentSubagentStopped", frame, cancellationToken);

        await using var db = await _dbFactory.CreateDbContextAsync(cancellationToken);
        var entity = await db.Sessions.FindAsync(new object?[] { sessionId }, cancellationToken);
        if (entity is null)
        {
            _logger.LogWarning("AgentSubagentStopped for unknown session {SessionId}.", sessionId);
            return;
        }
        entity.LastActivityAtUtc = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(cancellationToken);

        await BroadcastAsync(entity.UserId, "AgentSubagentStopped", frame, cancellationToken);
    }

    public async Task HandleNotifiedAsync(string sessionId, string workerConnectionId, AgentNotifiedFrame frame, CancellationToken cancellationToken)
    {
        if (!await EnsureWorkerOwnsSessionAsync(sessionId, workerConnectionId, cancellationToken)) return;

        await PersistEventAsync(sessionId, "AgentNotified", frame, cancellationToken);

        await using var db = await _dbFactory.CreateDbContextAsync(cancellationToken);
        var entity = await db.Sessions.FindAsync(new object?[] { sessionId }, cancellationToken);
        if (entity is null)
        {
            _logger.LogWarning("AgentNotified for unknown session {SessionId}.", sessionId);
            return;
        }
        entity.LastActivityAtUtc = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(cancellationToken);

        await BroadcastAsync(entity.UserId, "AgentNotified", frame, cancellationToken);
    }

    public async Task HandleCompactingAsync(string sessionId, string workerConnectionId, AgentCompactingFrame frame, CancellationToken cancellationToken)
    {
        if (!await EnsureWorkerOwnsSessionAsync(sessionId, workerConnectionId, cancellationToken)) return;

        await PersistEventAsync(sessionId, "AgentCompacting", frame, cancellationToken);

        await using var db = await _dbFactory.CreateDbContextAsync(cancellationToken);
        var entity = await db.Sessions.FindAsync(new object?[] { sessionId }, cancellationToken);
        if (entity is null)
        {
            _logger.LogWarning("AgentCompacting for unknown session {SessionId}.", sessionId);
            return;
        }
        entity.LastActivityAtUtc = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(cancellationToken);

        await BroadcastAsync(entity.UserId, "AgentCompacting", frame, cancellationToken);
    }

    /// <summary>
    /// Replay persisted activity events for a session. Used by the Console when reopening a
    /// session detail page so the activity timeline populates from history rather than only
    /// from live events received while the page is open.
    /// </summary>
    public async Task<IReadOnlyList<AgentActivityEntry>> ListEventsAsync(string sessionId, string userId, CancellationToken cancellationToken)
    {
        await using var db = await _dbFactory.CreateDbContextAsync(cancellationToken);
        var session = await db.Sessions.AsNoTracking()
            .Where(s => s.SessionId == sessionId)
            .Select(s => new { s.UserId })
            .FirstOrDefaultAsync(cancellationToken);
        if (session is null || session.UserId != userId) return Array.Empty<AgentActivityEntry>();

        var rows = await db.SessionAgentEvents.AsNoTracking()
            .Where(e => e.SessionId == sessionId)
            .OrderBy(e => e.Id)
            .Select(e => new { e.Id, e.EventType, e.PayloadJson, e.CreatedAtUtc })
            .ToArrayAsync(cancellationToken);

        return rows
            .Select(r => new AgentActivityEntry(r.Id, r.EventType, r.PayloadJson, r.CreatedAtUtc))
            .ToArray();
    }

    private async Task<bool> EnsureWorkerOwnsSessionAsync(string sessionId, string workerConnectionId, CancellationToken cancellationToken)
    {
        await using var db = await _dbFactory.CreateDbContextAsync(cancellationToken);
        var session = await db.Sessions.AsNoTracking()
            .Where(s => s.SessionId == sessionId)
            .Select(s => new { s.WorkerConnectionId })
            .FirstOrDefaultAsync(cancellationToken);
        if (session is null)
        {
            _logger.LogWarning("Agent event for unknown session {SessionId}.", sessionId);
            return false;
        }
        if (!string.Equals(session.WorkerConnectionId, workerConnectionId, StringComparison.Ordinal))
        {
            _logger.LogWarning("Agent event for session {SessionId} rejected: worker mismatch (expected={Expected}, actual={Actual}).", sessionId, session.WorkerConnectionId, workerConnectionId);
            return false;
        }
        return true;
    }

    private async Task PersistEventAsync(string sessionId, string eventType, object frame, CancellationToken cancellationToken)
    {
        await using var db = await _dbFactory.CreateDbContextAsync(cancellationToken);
        db.SessionAgentEvents.Add(new SessionAgentEventEntity
        {
            SessionId = sessionId,
            EventType = eventType,
            PayloadJson = JsonSerializer.Serialize(frame),
            CreatedAtUtc = DateTimeOffset.UtcNow,
        });
        await db.SaveChangesAsync(cancellationToken);
    }

    private Task BroadcastAsync<T>(string userId, string eventType, T frame, CancellationToken cancellationToken) where T : notnull
        => _terminalHub.Clients.User(userId).SendAsync("AgentActivity", new AgentActivityEnvelope(eventType, frame), cancellationToken);
}

public sealed record AgentActivityEnvelope(string EventType, object Frame);

public sealed record AgentActivityEntry(long Id, string EventType, string PayloadJson, DateTimeOffset CreatedAtUtc);
