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
    public async Task RecoverActiveSessionsAsync_LoadsAttachedSessionsAsDetachedGracePeriod()
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
        // Gateway restart severs the client connection but the worker shell is alive, so
        // Attached becomes DetachedGracePeriod (waiting for the client to reattach), not Recovering.
        session.AttachmentState.Should().Be(SessionAttachmentState.DetachedGracePeriod);
        session.WorkerConnectionId.Should().BeEmpty();
        session.AttachedClientConnectionId.Should().BeNull();
    }

    [Fact]
    public async Task RecoverActiveSessionsAsync_PreservesDetachedGracePeriodSessions()
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
            AttachmentState = "DetachedGracePeriod"
        });
        await db.SaveChangesAsync();

        await coordinator.RecoverActiveSessionsAsync();

        coordinator.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.DetachedGracePeriod);
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
            LastActivityAtUtc = DateTimeOffset.UtcNow, AttachmentState = "Recovering"
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
            LastActivityAtUtc = DateTimeOffset.UtcNow, AttachmentState = "Recovering"
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
    public async Task RecoveringSession_SurvivesDisconnectAndReboundsOnWorkerReconnect()
    {
        // sess_77b regression: a worker that blipped offline must not cost the session its
        // life. There is no wall-clock reaper anymore — the session stays Recovering until
        // the worker reconnects, then rebounds to Attached. The gateway does not judge worker
        // session liveness by a timer; only the worker's own report does that.
        var (coordinator, _) = CreateCoordinator();
        var sessionId = (await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), null, CancellationToken.None)).Response!.SessionId;
        coordinator.TryGetSession(sessionId, out var created).Should().BeTrue();
        created.AttachmentState.Should().Be(SessionAttachmentState.Attached);
        created.WorkerConnectionId.Should().Be("worker-conn-1");

        // Worker SignalR drops. Session → Recovering, but nothing reaps it now.
        await coordinator.TransitionToRecovering("worker-1", "worker-conn-1");
        coordinator.TryGetSession(sessionId, out var recovering).Should().BeTrue();
        recovering.AttachmentState.Should().Be(SessionAttachmentState.Recovering);
        recovering.ExitReason.Should().BeNull();

        // Worker reconnects (any time later — no expiry raced it). Live PTY rebounds.
        var reboundCount = await coordinator.RebindActiveSessions("user-1", "worker-1", "worker-conn-new");
        reboundCount.Should().Be(1);
        coordinator.TryGetSession(sessionId, out var live).Should().BeTrue();
        live.AttachmentState.Should().Be(SessionAttachmentState.Attached);
        live.WorkerConnectionId.Should().Be("worker-conn-new");
        live.ExitReason.Should().BeNull();
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

        // Step 1: Gateway restarts, recover sessions. The worker shell survived, so the
        // formerly-Attached session becomes DetachedGracePeriod (waiting for client reattach),
        // not Recovering.
        await coordinator.RecoverActiveSessionsAsync();
        coordinator.TryGetSession(sessionId, out var afterRecover).Should().BeTrue();
        afterRecover.AttachmentState.Should().Be(SessionAttachmentState.DetachedGracePeriod);

        // Step 2: Worker reconnects. Rebind only refreshes WorkerConnectionId for a
        // DetachedGracePeriod session — it does NOT transition to Attached (no client yet).
        var reboundCount = await coordinator.RebindActiveSessions("user-1", "worker-1", "worker-conn-reconnected");
        reboundCount.Should().Be(1);
        coordinator.TryGetSession(sessionId, out var afterRebind).Should().BeTrue();
        afterRebind.AttachmentState.Should().Be(SessionAttachmentState.DetachedGracePeriod);
        afterRebind.WorkerConnectionId.Should().Be("worker-conn-reconnected");

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

    [Fact]
    public async Task ReconcileWorkerSessionsAsync_ExpiresSessionsNotInSnapshot()
    {
        // Worker reconnects and reports which sessions it still holds. Sessions the worker no
        // longer knows about (shell died in a worker restart) must be expired so the client
        // does not see a dead terminal forever.
        var (coordinator, _) = CreateCoordinator();
        var keep1 = (await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), null, CancellationToken.None)).Response!.SessionId;
        var keep2 = (await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), null, CancellationToken.None)).Response!.SessionId;
        var ghost = (await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), null, CancellationToken.None)).Response!.SessionId;

        var detachAt = DateTimeOffset.UtcNow;
        await coordinator.DetachSessionAsync("user-1", keep1, detachAt, CancellationToken.None);
        await coordinator.DetachSessionAsync("user-1", keep2, detachAt, CancellationToken.None);
        await coordinator.DetachSessionAsync("user-1", ghost, detachAt, CancellationToken.None);

        var expired = await coordinator.ReconcileWorkerSessionsAsync("user-1", "worker-1",
            new HashSet<string> { keep1, keep2 });

        expired.Should().ContainSingle().Which.Should().Be(ghost);
        coordinator.TryGetSession(ghost, out var ghostSession).Should().BeTrue();
        ghostSession.AttachmentState.Should().Be(SessionAttachmentState.Expired);
        ghostSession.ExitReason.Should().Be("worker-restart");
        coordinator.TryGetSession(keep1, out var kept1).Should().BeTrue();
        kept1.AttachmentState.Should().Be(SessionAttachmentState.DetachedGracePeriod);
    }

    [Fact]
    public async Task ReconcileWorkerSessionsAsync_NeverExpiresAttachedSessions()
    {
        // CRITICAL safety invariant: an Attached session has a live client. The worker snapshot
        // is not authoritative for such sessions (a client could be reattaching concurrently),
        // so reconcile must NEVER expire Attached — otherwise it races the reattach and kills a
        // live terminal.
        var (coordinator, _) = CreateCoordinator();
        var attached = (await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), null, CancellationToken.None)).Response!.SessionId;
        attached.Should().NotBeNull();
        coordinator.TryGetSession(attached, out var afterCreate).Should().BeTrue();
        afterCreate.AttachmentState.Should().Be(SessionAttachmentState.Attached);

        var expired = await coordinator.ReconcileWorkerSessionsAsync("user-1", "worker-1", new HashSet<string>());

        expired.Should().BeEmpty();
        coordinator.TryGetSession(attached, out var stillAttached).Should().BeTrue();
        stillAttached.AttachmentState.Should().Be(SessionAttachmentState.Attached);
    }

    [Fact]
    public async Task ReconcileWorkerSessionsAsync_SnapshotIncludesAll_DoesNothing()
    {
        var (coordinator, _) = CreateCoordinator();
        var keep1 = (await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), null, CancellationToken.None)).Response!.SessionId;
        var keep2 = (await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), null, CancellationToken.None)).Response!.SessionId;
        var detachAt = DateTimeOffset.UtcNow;
        await coordinator.DetachSessionAsync("user-1", keep1, detachAt, CancellationToken.None);
        await coordinator.DetachSessionAsync("user-1", keep2, detachAt, CancellationToken.None);

        var expired = await coordinator.ReconcileWorkerSessionsAsync("user-1", "worker-1",
            new HashSet<string> { keep1, keep2 });

        expired.Should().BeEmpty();
        coordinator.TryGetSession(keep1, out var k1).Should().BeTrue();
        k1.AttachmentState.Should().Be(SessionAttachmentState.DetachedGracePeriod);
    }

    [Fact]
    public async Task ReconcileWorkerSessionsAsync_DoesNotTouchSessionsForOtherWorker()
    {
        // The snapshot reported by worker-other only speaks for worker-other's sessions.
        // A session owned by worker-1 must NOT be expired when reconciling worker-other,
        // even with an empty snapshot.
        var (coordinator, _) = CreateCoordinator();
        var sessionId = (await coordinator.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), null, CancellationToken.None)).Response!.SessionId;
        await coordinator.DetachSessionAsync("user-1", sessionId, DateTimeOffset.UtcNow, CancellationToken.None);

        var expired = await coordinator.ReconcileWorkerSessionsAsync("user-1", "worker-other", new HashSet<string>());

        expired.Should().BeEmpty();
        coordinator.TryGetSession(sessionId, out var session).Should().BeTrue();
        session.AttachmentState.Should().Be(SessionAttachmentState.DetachedGracePeriod);
    }

    private static (PostgresSessionCoordinator coordinator, AppDbContext db) CreateCoordinator()
    {
        var services = new ServiceCollection();
        var dbId = $"recovery_test_{Guid.NewGuid():N}";
        services.AddDbContextFactory<AppDbContext>(options =>
            options.UseInMemoryDatabase(dbId));
        var serviceProvider = services.BuildServiceProvider();

        var contextFactory = serviceProvider.GetRequiredService<IDbContextFactory<AppDbContext>>();
        var db = serviceProvider.GetRequiredService<AppDbContext>();
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1");
        var logger = LoggerFactory.Create(_ => { }).CreateLogger<PostgresSessionCoordinator>();

        var coordinator = new PostgresSessionCoordinator(workers, contextFactory, logger);
        return (coordinator, db);
    }
}
