using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Audit;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Stats;
using CortexTerminal.Gateway.Tests.Sessions.Fakes;
using CortexTerminal.Gateway.Tests.Workers;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Hubs;

public sealed class WorkerHubArtifactRpcTests
{
    private sealed class HubStack : IAsyncDisposable
    {
        public required PostgresWorkerRegistry Workers { get; init; }
        public required PostgresSessionCoordinator Sessions { get; init; }
        public required IDbContextFactory<AppDbContext> Db { get; init; }
        public required ArtifactService Artifacts { get; init; }
        public required FakeArtifactStorage Storage { get; init; }
        public required ArtifactTestHubContext TerminalHub { get; init; }
        public required RecordingArtifactCommandDispatcher Dispatcher { get; init; }
        public required WorkerHub Hub { get; init; }
        public required ReplayCoordinator Replay { get; init; }
        public required string WorkerId { get; init; }
        public required string WorkerConnId { get; init; }
        public required string OwnerUserId { get; init; }

        public async ValueTask DisposeAsync()
        {
            await using var ctx = await Db.CreateDbContextAsync(CancellationToken.None);
            await ctx.Artifacts.ExecuteDeleteAsync(CancellationToken.None);
        }
    }

    private static async Task<HubStack> BuildAsync(string ownerId = "user-1")
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1", ownerUserId: ownerId);
        var storage = new FakeArtifactStorage();
        var terminalHub = new ArtifactTestHubContext(ownerId);
        var dispatcher = new RecordingArtifactCommandDispatcher();
        var (db, sessions, artifacts) = TestSessionFactory.CreateArtifactService(workers, storage, terminalHub, dispatcher);
        var replay = new ReplayCoordinator();
        var agentActivity = TestSessionFactory.CreateAgentActivityService(terminalHub);
        var hub = (WorkerHub)Activator.CreateInstance(
            typeof(WorkerHub),
            workers,
            sessions,
            replay,
            new NullAuditLogStore(),
            new TestHubContext<TerminalHub>(new Dictionary<string, IClientProxy>()),
            new NoOpStatsService(),
            new NoOpSessionStatsService(),
            artifacts,
            agentActivity,
            NullLogger<WorkerHub>.Instance)!;
        // Create a session for the owner so we can hand the sessionId into the artifact flow.
        var create = await sessions.CreateSessionAsync(ownerId, new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        hub.Context = new TestHubCallerContext("worker-conn-1", ownerId);
        hub.Clients = new TestHubCallerClients(new RecordingClientProxy());
        return new HubStack
        {
            Workers = workers,
            Sessions = sessions,
            Db = db,
            Artifacts = artifacts,
            Storage = storage,
            TerminalHub = terminalHub,
            Dispatcher = dispatcher,
            Hub = hub,
            Replay = replay,
            WorkerId = "worker-1",
            WorkerConnId = "worker-conn-1",
            OwnerUserId = ownerId,
        };
    }

    private static async Task<string> GetSessionIdAsync(HubStack s)
    {
        var list = await s.Sessions.GetSessionsForUser(s.OwnerUserId);
        return list[0].SessionId;
    }

    [Fact]
    public async Task RequestArtifactUploadUrl_OwnedSession_ReturnsUrlAndPersistsPendingRow()
    {
        var s = await BuildAsync();
        var sessionId = await GetSessionIdAsync(s);
        var request = new CreateArtifactRequest(sessionId, "worker.txt", 12, "sha", ArtifactOrigin.Worker);

        var resp = await s.Hub.RequestArtifactUploadUrl(request);

        resp.UploadUrl.Should().StartWith("https://fake-s3.local/");
        resp.ArtifactId.Should().NotBeEmpty();
        await using var ctx = await s.Db.CreateDbContextAsync(CancellationToken.None);
        var entity = await ctx.Artifacts.SingleAsync(a => a.SessionId == sessionId && a.Filename == "worker.txt", CancellationToken.None);
        entity.Status.Should().Be(ArtifactStatus.Pending);
        entity.Origin.Should().Be(ArtifactOrigin.Worker);
        entity.OwnerUserId.Should().Be(s.OwnerUserId);
    }

    [Fact]
    public async Task RequestArtifactUploadUrl_WorkerConnectionMissing_ThrowsHubException()
    {
        var s = await BuildAsync();
        s.Hub.Context = new TestHubCallerContext("unknown-connection");
        var sessionId = await GetSessionIdAsync(s);
        var request = new CreateArtifactRequest(sessionId, "worker.txt", 12, "sha", ArtifactOrigin.Worker);

        var act = () => s.Hub.RequestArtifactUploadUrl(request);

        await act.Should().ThrowAsync<HubException>();
    }

    [Fact]
    public async Task RequestArtifactUploadUrl_WorkerWithoutOwner_ThrowsHubException()
    {
        var s = await BuildAsync();
        // Register a second worker with no owner and repoint context at it.
        s.Workers.Register("worker-bare", "bare-conn");
        s.Hub.Context = new TestHubCallerContext("bare-conn");
        var sessionId = await GetSessionIdAsync(s);
        var request = new CreateArtifactRequest(sessionId, "worker.txt", 12, "sha", ArtifactOrigin.Worker);

        var act = () => s.Hub.RequestArtifactUploadUrl(request);

        await act.Should().ThrowAsync<HubException>();
    }

    [Fact]
    public async Task CompleteArtifactUpload_ReadyArtifact_BroadcastsArtifactChangedToOwner()
    {
        var s = await BuildAsync();
        var sessionId = await GetSessionIdAsync(s);
        var create = await s.Hub.RequestArtifactUploadUrl(new CreateArtifactRequest(sessionId, "worker.txt", 12, "sha1", ArtifactOrigin.Worker));
        s.Storage.Seed(sessionId, "worker.txt", new byte[12]);

        var ack = await s.Hub.CompleteArtifactUpload(new CompleteArtifactRequest(create.ArtifactId, "deadbeef"));

        ack.Success.Should().BeTrue();
        ack.Error.Should().BeNull();
        var broadcast = s.TerminalHub.Users[s.OwnerUserId].Invocations
            .Where(i => i.Method == "ArtifactChanged")
            .Select(i => (ArtifactChangedEvent)i.Arguments[0]!)
            .Single();
        broadcast.ChangeType.Should().Be(ArtifactChangeType.Created);
        broadcast.Artifact!.Filename.Should().Be("worker.txt");
    }

    [Fact]
    public async Task CompleteArtifactUpload_ShaMismatch_PropagatesErrorAsFailedAck()
    {
        var s = await BuildAsync();
        var sessionId = await GetSessionIdAsync(s);
        var create = await s.Hub.RequestArtifactUploadUrl(new CreateArtifactRequest(sessionId, "worker.txt", 12, "sha1", ArtifactOrigin.Worker));
        // No seed → storage reports the object missing → CompleteWorkerUploadAsync throws InvalidOperationException.

        var ack = await s.Hub.CompleteArtifactUpload(new CompleteArtifactRequest(create.ArtifactId, "deadbeef"));

        ack.Success.Should().BeFalse();
        ack.Error.Should().NotBeNullOrEmpty();
    }

    [Fact]
    public async Task CompleteArtifactUpload_WorkerConnectionMissing_ThrowsHubException()
    {
        var s = await BuildAsync();
        s.Hub.Context = new TestHubCallerContext("unknown-connection");

        var act = () => s.Hub.CompleteArtifactUpload(new CompleteArtifactRequest("any", "sha"));

        await act.Should().ThrowAsync<HubException>();
    }

    [Fact]
    public async Task ReportArtifactDeleted_OwnedSession_SoftDeletesAndBroadcasts()
    {
        var s = await BuildAsync();
        var sessionId = await GetSessionIdAsync(s);
        var create = await s.Hub.RequestArtifactUploadUrl(new CreateArtifactRequest(sessionId, "worker.txt", 12, "sha1", ArtifactOrigin.Worker));
        s.Storage.Seed(sessionId, "worker.txt", new byte[12]);
        await s.Hub.CompleteArtifactUpload(new CompleteArtifactRequest(create.ArtifactId, "deadbeef"));

        await s.Hub.ReportArtifactDeleted(new ReportArtifactDeletedFrame(sessionId, "worker.txt"));

        await using var ctx = await s.Db.CreateDbContextAsync(CancellationToken.None);
        var entity = await ctx.Artifacts.SingleAsync(a => a.SessionId == sessionId && a.Filename == "worker.txt", CancellationToken.None);
        entity.Status.Should().Be(ArtifactStatus.Deleted);
        var deletes = s.TerminalHub.Users[s.OwnerUserId].Invocations
            .Where(i => i.Method == "ArtifactChanged")
            .Select(i => (ArtifactChangedEvent)i.Arguments[0]!)
            .ToList();
        deletes.Last().ChangeType.Should().Be(ArtifactChangeType.Deleted);
        deletes.Last().Artifact.Should().BeNull();
    }

    [Fact]
    public async Task ReportArtifactDeleted_SessionOwnedByOtherWorker_IsSilentNoOp()
    {
        var s = await BuildAsync();
        var sessionId = await GetSessionIdAsync(s);
        var create = await s.Hub.RequestArtifactUploadUrl(new CreateArtifactRequest(sessionId, "worker.txt", 12, "sha1", ArtifactOrigin.Worker));
        s.Storage.Seed(sessionId, "worker.txt", new byte[12]);
        await s.Hub.CompleteArtifactUpload(new CompleteArtifactRequest(create.ArtifactId, "deadbeef"));

        // Pretend a different worker connection calls ReportArtifactDeleted.
        s.Hub.Context = new TestHubCallerContext("another-worker-conn");

        await s.Hub.ReportArtifactDeleted(new ReportArtifactDeletedFrame(sessionId, "worker.txt"));

        await using var ctx = await s.Db.CreateDbContextAsync(CancellationToken.None);
        var entity = await ctx.Artifacts.SingleAsync(a => a.SessionId == sessionId && a.Filename == "worker.txt", CancellationToken.None);
        entity.Status.Should().Be(ArtifactStatus.Ready); // unchanged
    }

    [Fact]
    public async Task ReportArtifactDeleted_UnknownWorker_IsSilentNoOp()
    {
        var s = await BuildAsync();
        var sessionId = await GetSessionIdAsync(s);
        s.Hub.Context = new TestHubCallerContext("unregistered-conn");

        await s.Hub.ReportArtifactDeleted(new ReportArtifactDeletedFrame(sessionId, "worker.txt"));

        s.TerminalHub.Users.Values.SelectMany(p => p.Invocations).Should().BeEmpty();
    }
}
