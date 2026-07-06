using System.Text.Json;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Tests.Hubs;
using CortexTerminal.Gateway.Tests.Sessions.Fakes;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Sessions;

/// <summary>
/// Title-update handler — verifies AgentActivityService overwrites InferredTitle unconditionally
/// (Claude's choice beats the first-prompt truncation), broadcasts the structured frame to every
/// Console client owned by the user, and rejects events from a worker that doesn't own the
/// session.
/// </summary>
public sealed class AgentActivityServiceTitleTests
{
    private sealed class Stack : IAsyncDisposable
    {
        public required IDbContextFactory<AppDbContext> Db { get; init; }
        public required PostgresSessionCoordinator Sessions { get; init; }
        public required PostgresWorkerRegistry Workers { get; init; }
        public required AgentActivityService Service { get; init; }
        public required ArtifactTestHubContext Hub { get; init; }
        public required string OwnerUserId { get; init; }
        public required string WorkerId { get; init; }
        public required string WorkerConnId { get; init; }

        public async ValueTask DisposeAsync()
        {
            await using var ctx = await Db.CreateDbContextAsync(CancellationToken.None);
            await ctx.SessionAgentEvents.ExecuteDeleteAsync(CancellationToken.None);
        }
    }

    private static async Task<Stack> BuildAsync(string ownerId = "user-1")
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1", ownerUserId: ownerId);
        var hub = new ArtifactTestHubContext(ownerId);

        var services = new ServiceCollection();
        var dbName = $"title-test-{Guid.NewGuid():N}";
        services.AddDbContextFactory<AppDbContext>(o => o.UseInMemoryDatabase(dbName));
        var sp = services.BuildServiceProvider();
        var db = sp.GetRequiredService<IDbContextFactory<AppDbContext>>();

        var sessions = new PostgresSessionCoordinator(
            workers,
            db,
            LoggerFactory.Create(_ => { }).CreateLogger<PostgresSessionCoordinator>(),
            timeProvider: null);

        var service = new AgentActivityService(
            db,
            hub,
            LoggerFactory.Create(_ => { }).CreateLogger<AgentActivityService>());

        await sessions.CreateSessionAsync(ownerId, new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);

        return new Stack
        {
            Db = db,
            Sessions = sessions,
            Workers = workers,
            Service = service,
            Hub = hub,
            OwnerUserId = ownerId,
            WorkerId = "worker-1",
            WorkerConnId = "worker-conn-1",
        };
    }

    private static async Task<string> GetSessionIdAsync(Stack s)
    {
        var list = await s.Sessions.GetSessionsForUser(s.OwnerUserId);
        return list[0].SessionId;
    }

    [Fact]
    public async Task HandleTitleUpdatedAsync_OverwritesExistingInferredTitle()
    {
        var s = await BuildAsync();
        var sessionId = await GetSessionIdAsync(s);

        // Seed an existing title (the first-prompt truncation path sets this).
        await using (var seedCtx = await s.Db.CreateDbContextAsync(CancellationToken.None))
        {
            var entity = await seedCtx.Sessions.SingleAsync(e => e.SessionId == sessionId, CancellationToken.None);
            entity.InferredTitle = "old title";
            await seedCtx.SaveChangesAsync(CancellationToken.None);
        }

        await s.Service.HandleTitleUpdatedAsync(
            sessionId,
            s.WorkerConnId,
            new AgentTitleUpdatedFrame(sessionId, "New Title From Claude"),
            CancellationToken.None);

        await using var verifyCtx = await s.Db.CreateDbContextAsync(CancellationToken.None);
        var row = await verifyCtx.Sessions.AsNoTracking().SingleAsync(e => e.SessionId == sessionId, CancellationToken.None);
        row.InferredTitle.Should().Be("New Title From Claude");
    }

    [Fact]
    public async Task HandleTitleUpdatedAsync_BroadcastsToUserViaSignalR()
    {
        var s = await BuildAsync();
        var sessionId = await GetSessionIdAsync(s);

        await s.Service.HandleTitleUpdatedAsync(
            sessionId,
            s.WorkerConnId,
            new AgentTitleUpdatedFrame(sessionId, "Live Title"),
            CancellationToken.None);

        var proxy = s.Hub.Users[s.OwnerUserId];
        var invocation = proxy.Invocations.Should().ContainSingle(i => i.Method == "AgentActivity").Subject;
        var envelope = (AgentActivityEnvelope)invocation.Arguments[0]!;
        envelope.EventType.Should().Be("AgentTitleUpdated");
        var parsed = JsonDocument.Parse(envelope.FrameJson).RootElement;
        parsed.GetProperty("title").GetString().Should().Be("Live Title");
        parsed.GetProperty("sessionId").GetString().Should().Be(sessionId);
    }

    [Fact]
    public async Task HandleTitleUpdatedAsync_TruncatesOverlongTitle()
    {
        var s = await BuildAsync();
        var sessionId = await GetSessionIdAsync(s);
        var longTitle = new string('a', 250);

        await s.Service.HandleTitleUpdatedAsync(
            sessionId,
            s.WorkerConnId,
            new AgentTitleUpdatedFrame(sessionId, longTitle),
            CancellationToken.None);

        await using var verifyCtx = await s.Db.CreateDbContextAsync(CancellationToken.None);
        var row = await verifyCtx.Sessions.AsNoTracking().SingleAsync(e => e.SessionId == sessionId, CancellationToken.None);
        // AgentActivityService.InferredTitleMaxLength == 200.
        row.InferredTitle!.Length.Should().Be(200);
    }

    [Fact]
    public async Task HandleTitleUpdatedAsync_RejectsEventFromWrongWorker()
    {
        var s = await BuildAsync();
        var sessionId = await GetSessionIdAsync(s);

        await using (var seedCtx = await s.Db.CreateDbContextAsync(CancellationToken.None))
        {
            var entity = await seedCtx.Sessions.SingleAsync(e => e.SessionId == sessionId, CancellationToken.None);
            entity.InferredTitle = "preserved";
            await seedCtx.SaveChangesAsync(CancellationToken.None);
        }

        await s.Service.HandleTitleUpdatedAsync(
            sessionId,
            workerConnectionId: "some-other-conn",
            new AgentTitleUpdatedFrame(sessionId, "attacker title"),
            CancellationToken.None);

        await using var verifyCtx = await s.Db.CreateDbContextAsync(CancellationToken.None);
        var row = await verifyCtx.Sessions.AsNoTracking().SingleAsync(e => e.SessionId == sessionId, CancellationToken.None);
        row.InferredTitle.Should().Be("preserved");
        s.Hub.Users[s.OwnerUserId].Invocations.Should().BeEmpty();
    }

    [Fact]
    public async Task HandleTitleUpdatedAsync_PersistsEventForReplay()
    {
        var s = await BuildAsync();
        var sessionId = await GetSessionIdAsync(s);

        await s.Service.HandleTitleUpdatedAsync(
            sessionId,
            s.WorkerConnId,
            new AgentTitleUpdatedFrame(sessionId, "Persisted"),
            CancellationToken.None);

        // ListEventsAsync is the replay path the Console hits on session reopen.
        var events = await s.Service.ListEventsAsync(sessionId, s.OwnerUserId, CancellationToken.None);
        var titleEvent = events.Should().ContainSingle(e => e.EventType == "AgentTitleUpdated").Subject;
        titleEvent.PayloadJson.Should().Contain("Persisted");
    }

    [Fact]
    public async Task HandleTitleUpdatedAsync_NullTitle_ClearsInferredTitle()
    {
        var s = await BuildAsync();
        var sessionId = await GetSessionIdAsync(s);

        await using (var seedCtx = await s.Db.CreateDbContextAsync(CancellationToken.None))
        {
            var entity = await seedCtx.Sessions.SingleAsync(e => e.SessionId == sessionId, CancellationToken.None);
            entity.InferredTitle = "previous";
            await seedCtx.SaveChangesAsync(CancellationToken.None);
        }

        await s.Service.HandleTitleUpdatedAsync(
            sessionId,
            s.WorkerConnId,
            new AgentTitleUpdatedFrame(sessionId, null!),
            CancellationToken.None);

        await using var verifyCtx = await s.Db.CreateDbContextAsync(CancellationToken.None);
        var row = await verifyCtx.Sessions.AsNoTracking().SingleAsync(e => e.SessionId == sessionId, CancellationToken.None);
        // frame.Title?.Trim() ?? string.Empty collapses null to empty.
        row.InferredTitle.Should().Be("");
    }

    [Fact]
    public async Task HandleTitleUpdatedAsync_WhitespaceTitle_ClearsInferredTitle()
    {
        var s = await BuildAsync();
        var sessionId = await GetSessionIdAsync(s);

        await s.Service.HandleTitleUpdatedAsync(
            sessionId,
            s.WorkerConnId,
            new AgentTitleUpdatedFrame(sessionId, "    "),
            CancellationToken.None);

        await using var verifyCtx = await s.Db.CreateDbContextAsync(CancellationToken.None);
        var row = await verifyCtx.Sessions.AsNoTracking().SingleAsync(e => e.SessionId == sessionId, CancellationToken.None);
        // Trim() collapses whitespace-only to empty.
        row.InferredTitle.Should().Be("");
    }

    [Fact]
    public async Task HandleTitleUpdatedAsync_UnknownSession_DoesNothing()
    {
        var s = await BuildAsync();
        var realSessionId = await GetSessionIdAsync(s);

        // A session id that was never created — EnsureWorkerOwnsSessionAsync returns false before
        // any persist or broadcast happens, so the unknown id cannot mutate real state.
        await s.Service.HandleTitleUpdatedAsync(
            "no-such-session",
            s.WorkerConnId,
            new AgentTitleUpdatedFrame("no-such-session", "Ghost"),
            CancellationToken.None);

        s.Hub.Users[s.OwnerUserId].Invocations.Should().BeEmpty();
        var events = await s.Service.ListEventsAsync(realSessionId, s.OwnerUserId, CancellationToken.None);
        events.Should().BeEmpty();
    }
}
