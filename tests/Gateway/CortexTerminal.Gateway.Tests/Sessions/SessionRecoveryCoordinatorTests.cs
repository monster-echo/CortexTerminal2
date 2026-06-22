using System.Collections.Concurrent;
using System.Reflection;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Sessions;

public sealed class SessionRecoveryCoordinatorTests
{
    [Fact]
    public async Task RecoverActiveSessionsAsync_LoadsAttachedSessionsAsRecovering()
    {
        var (coordinator, db) = CreateCoordinator();
        var sessionId = $"sess_{Guid.NewGuid():N}";
        db.Sessions.Add(new SessionRecordEntity
        {
            SessionId = sessionId,
            UserId = "user-1",
            WorkerId = "worker-1",
            Columns = 120,
            Rows = 40,
            CreatedAtUtc = DateTimeOffset.UtcNow,
            LastActivityAtUtc = DateTimeOffset.UtcNow,
            AttachmentState = "Attached"
        });
        await db.SaveChangesAsync();

        await coordinator.RecoverActiveSessionsAsync();

        coordinator.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Recovering);
        session.WorkerConnectionId.Should().BeEmpty();
        session.AttachedClientConnectionId.Should().BeNull();
    }

    [Fact]
    public async Task RecoverActiveSessionsAsync_LoadsDetachedGracePeriodSessionsAsRecovering()
    {
        var (coordinator, db) = CreateCoordinator();
        var sessionId = $"sess_{Guid.NewGuid():N}";
        db.Sessions.Add(new SessionRecordEntity
        {
            SessionId = sessionId,
            UserId = "user-1",
            WorkerId = "worker-1",
            Columns = 120,
            Rows = 40,
            CreatedAtUtc = DateTimeOffset.UtcNow,
            LastActivityAtUtc = DateTimeOffset.UtcNow,
            AttachmentState = "DetachedGracePeriod",
            LeaseExpiresAtUtc = DateTimeOffset.UtcNow.AddMinutes(3)
        });
        await db.SaveChangesAsync();

        await coordinator.RecoverActiveSessionsAsync();

        coordinator.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Recovering);
        session.LeaseExpiresAtUtc.Should().BeNull();
    }

    [Fact]
    public async Task RecoverActiveSessionsAsync_SkipsExpiredAndExitedSessions()
    {
        var (coordinator, db) = CreateCoordinator();
        var expiredId = $"sess_{Guid.NewGuid():N}";
        var exitedId = $"sess_{Guid.NewGuid():N}";
        db.Sessions.Add(new SessionRecordEntity
        {
            SessionId = expiredId, UserId = "user-1", WorkerId = "worker-1",
            Columns = 120, Rows = 40, CreatedAtUtc = DateTimeOffset.UtcNow,
            LastActivityAtUtc = DateTimeOffset.UtcNow, AttachmentState = "Expired"
        });
        db.Sessions.Add(new SessionRecordEntity
        {
            SessionId = exitedId, UserId = "user-1", WorkerId = "worker-1",
            Columns = 120, Rows = 40, CreatedAtUtc = DateTimeOffset.UtcNow,
            LastActivityAtUtc = DateTimeOffset.UtcNow, AttachmentState = "Exited"
        });
        await db.SaveChangesAsync();

        await coordinator.RecoverActiveSessionsAsync();

        coordinator.TryGetSession(expiredId, out _).Should().BeFalse();
        coordinator.TryGetSession(exitedId, out _).Should().BeFalse();
    }

    [Fact]
    public async Task RecoverActiveSessionsAsync_EmptyDatabase_DoesNothing()
    {
        var (coordinator, _) = CreateCoordinator();

        await coordinator.RecoverActiveSessionsAsync();

        // No exception thrown, no sessions loaded
        (await coordinator.GetSessionsForUser("user-1")).Should().BeEmpty();
    }

    [Fact]
    public async Task RebindActiveSessions_TransitionsRecoveringToAttached()
    {
        var (coordinator, db) = CreateCoordinator();
        var sessionId = $"sess_{Guid.NewGuid():N}";
        db.Sessions.Add(new SessionRecordEntity
        {
            SessionId = sessionId, UserId = "user-1", WorkerId = "worker-1",
            Columns = 120, Rows = 40, CreatedAtUtc = DateTimeOffset.UtcNow,
            LastActivityAtUtc = DateTimeOffset.UtcNow, AttachmentState = "Attached"
        });
        await db.SaveChangesAsync();
        await coordinator.RecoverActiveSessionsAsync();

        var reboundCount = await coordinator.RebindActiveSessions("user-1", "worker-1", "worker-conn-new");

        reboundCount.Should().Be(1);
        coordinator.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Attached);
        session.WorkerConnectionId.Should().Be("worker-conn-new");
    }

    [Fact]
    public async Task ReattachSessionAsync_RecoveringSession_ReturnsSuccessAndTransitionsToAttached()
    {
        var (coordinator, db) = CreateCoordinator();
        var sessionId = $"sess_{Guid.NewGuid():N}";
        db.Sessions.Add(new SessionRecordEntity
        {
            SessionId = sessionId, UserId = "user-1", WorkerId = "worker-1",
            Columns = 120, Rows = 40, CreatedAtUtc = DateTimeOffset.UtcNow,
            LastActivityAtUtc = DateTimeOffset.UtcNow, AttachmentState = "Attached"
        });
        await db.SaveChangesAsync();
        await coordinator.RecoverActiveSessionsAsync();

        var result = await coordinator.ReattachSessionAsync(
            "user-1",
            new ReattachSessionRequest(sessionId),
            "client-new",
            DateTimeOffset.UtcNow,
            CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        coordinator.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.Attached);
        session.AttachedClientConnectionId.Should().Be("client-new");
        session.ReplayPending.Should().BeFalse();
    }

    [Fact]
    public async Task ReattachSessionAsync_RecoveringSession_WrongUser_ReturnsNotFound()
    {
        var (coordinator, db) = CreateCoordinator();
        var sessionId = $"sess_{Guid.NewGuid():N}";
        db.Sessions.Add(new SessionRecordEntity
        {
            SessionId = sessionId, UserId = "user-1", WorkerId = "worker-1",
            Columns = 120, Rows = 40, CreatedAtUtc = DateTimeOffset.UtcNow,
            LastActivityAtUtc = DateTimeOffset.UtcNow, AttachmentState = "Attached"
        });
        await db.SaveChangesAsync();
        await coordinator.RecoverActiveSessionsAsync();

        var result = await coordinator.ReattachSessionAsync(
            "user-2",
            new ReattachSessionRequest(sessionId),
            "client-new",
            DateTimeOffset.UtcNow,
            CancellationToken.None);

        result.IsSuccess.Should().BeFalse();
        result.ErrorCode.Should().Be("session-not-found");
    }

    [Fact]
    public async Task ExpireRecoveringSessions_ExpiresSessionsOlderThanCutoff()
    {
        var (coordinator, db) = CreateCoordinator();
        var oldSessionId = $"sess_{Guid.NewGuid():N}";
        var recentSessionId = $"sess_{Guid.NewGuid():N}";
        var now = DateTimeOffset.UtcNow;

        db.Sessions.Add(new SessionRecordEntity
        {
            SessionId = oldSessionId, UserId = "user-1", WorkerId = "worker-1",
            Columns = 120, Rows = 40, CreatedAtUtc = now.AddMinutes(-5),
            LastActivityAtUtc = now.AddMinutes(-2), AttachmentState = "Attached"
        });
        db.Sessions.Add(new SessionRecordEntity
        {
            SessionId = recentSessionId, UserId = "user-1", WorkerId = "worker-1",
            Columns = 120, Rows = 40, CreatedAtUtc = now,
            LastActivityAtUtc = now, AttachmentState = "Attached"
        });
        await db.SaveChangesAsync();
        await coordinator.RecoverActiveSessionsAsync();

        // Recovery sets LastActivityAtUtc = now, so reset the old session's timestamp back
        var sessionsDict = (ConcurrentDictionary<string, SessionRecord>)coordinator.GetType()
            .GetField("_sessions", BindingFlags.Instance | BindingFlags.NonPublic)!
            .GetValue(coordinator)!;
        sessionsDict[oldSessionId] = sessionsDict[oldSessionId] with
        {
            LastActivityAtUtc = now.AddMinutes(-2)
        };

        // Cutoff is 60 seconds ago - old session (2 min ago) should expire, recent should not
        var expiredIds = await coordinator.ExpireRecoveringSessions(now.AddSeconds(-60));

        expiredIds.Should().ContainSingle().Which.Should().Be(oldSessionId);
        coordinator.TryGetSession(oldSessionId, out var expired).Should().BeTrue();
        expired.AttachmentState.Should().Be(SessionAttachmentState.Expired);
        expired.ExitReason.Should().Be("recovery-timeout");
        coordinator.TryGetSession(recentSessionId, out var recent).Should().BeTrue();
        recent.AttachmentState.Should().Be(SessionAttachmentState.Recovering);
    }

    [Fact]
    public async Task ExpireRecoveringSessions_NoRecoveringSessions_ReturnsEmpty()
    {
        var (coordinator, _) = CreateCoordinator();

        var expiredIds = await coordinator.ExpireRecoveringSessions(DateTimeOffset.UtcNow);

        expiredIds.Should().BeEmpty();
    }

    [Fact]
    public async Task FullRecoveryFlow_RecoverThenRebindThenReattach()
    {
        var (coordinator, db) = CreateCoordinator();
        var sessionId = $"sess_{Guid.NewGuid():N}";
        db.Sessions.Add(new SessionRecordEntity
        {
            SessionId = sessionId, UserId = "user-1", WorkerId = "worker-1",
            Columns = 120, Rows = 40, CreatedAtUtc = DateTimeOffset.UtcNow,
            LastActivityAtUtc = DateTimeOffset.UtcNow, AttachmentState = "Attached"
        });
        await db.SaveChangesAsync();

        // Step 1: Gateway restarts, recover sessions
        await coordinator.RecoverActiveSessionsAsync();
        coordinator.TryGetSession(sessionId, out var recovering).Should().BeTrue();
        recovering.AttachmentState.Should().Be(SessionAttachmentState.Recovering);

        // Step 2: Worker reconnects
        var reboundCount = await coordinator.RebindActiveSessions("user-1", "worker-1", "worker-conn-reconnected");
        reboundCount.Should().Be(1);
        coordinator.TryGetSession(sessionId, out var attached).Should().BeTrue();
        attached.AttachmentState.Should().Be(SessionAttachmentState.Attached);
        attached.WorkerConnectionId.Should().Be("worker-conn-reconnected");

        // Step 3: Client reconnects and reattaches
        var result = await coordinator.ReattachSessionAsync(
            "user-1",
            new ReattachSessionRequest(sessionId),
            "client-reconnected",
            DateTimeOffset.UtcNow,
            CancellationToken.None);
        result.IsSuccess.Should().BeTrue();
        coordinator.TryGetSession(sessionId, out var live).Should().BeTrue();
        live.AttachmentState.Should().Be(SessionAttachmentState.Attached);
        live.AttachedClientConnectionId.Should().Be("client-reconnected");
    }

    private static (PostgresSessionCoordinator coordinator, AppDbContext db) CreateCoordinator()
    {
        var services = new ServiceCollection();
        var dbId = $"recovery_test_{Guid.NewGuid():N}";
        services.AddDbContext<AppDbContext>(options =>
            options.UseInMemoryDatabase(dbId));
        var serviceProvider = services.BuildServiceProvider();

        var scopeFactory = serviceProvider.GetRequiredService<IServiceScopeFactory>();
        var db = serviceProvider.GetRequiredService<AppDbContext>();
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var logger = LoggerFactory.Create(_ => { }).CreateLogger<PostgresSessionCoordinator>();

        var coordinator = new PostgresSessionCoordinator(workers, scopeFactory, logger);
        return (coordinator, db);
    }
}
