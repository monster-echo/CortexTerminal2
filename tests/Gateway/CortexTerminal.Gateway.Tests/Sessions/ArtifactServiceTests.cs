using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Audit;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Storage;
using CortexTerminal.Gateway.Tests.Hubs;
using CortexTerminal.Gateway.Tests.Sessions.Fakes;
using CortexTerminal.Gateway.Workers;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Sessions;

public sealed class ArtifactServiceTests
{
    private record ArtifactFixture(
        IDbContextFactory<AppDbContext> Db,
        ISessionCoordinator Sessions,
        ArtifactService Artifacts,
        FakeArtifactStorage Storage,
        RecordingArtifactCommandDispatcher Dispatcher,
        ArtifactTestHubContext Hub,
        RecordingAuditLogStore AuditLog,
        string SessionId,
        string OwnerId,
        string WorkerConnId);

    private static async Task<ArtifactFixture> SetupAsync(
        string ownerId = "user-1",
        string workerId = "worker-1",
        string workerConnId = "worker-conn-1",
        ArtifactStorageOptions? options = null)
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register(workerId, workerConnId, ownerUserId: ownerId);
        var storage = new FakeArtifactStorage();
        var hub = new ArtifactTestHubContext(ownerId);
        var dispatcher = new RecordingArtifactCommandDispatcher();
        var auditLog = new RecordingAuditLogStore();
        var (db, sessions, artifacts) = TestSessionFactory.CreateArtifactService(
            workers, storage, hub, dispatcher, options: options, auditLog: auditLog);
        var create = await sessions.CreateSessionAsync(ownerId, new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        return new ArtifactFixture(db, sessions, artifacts, storage, dispatcher, hub, auditLog, create.Response!.SessionId, ownerId, workerConnId);
    }

    private static async Task<ArtifactEntity> GetArtifactAsync(IDbContextFactory<AppDbContext> db, string sessionId, string filename)
    {
        await using var ctx = await db.CreateDbContextAsync(CancellationToken.None);
        return await ctx.Artifacts.SingleAsync(a => a.SessionId == sessionId && a.Filename == filename, CancellationToken.None);
    }

    private static async Task<ArtifactEntity?> FindArtifactAsync(IDbContextFactory<AppDbContext> db, string artifactId)
    {
        await using var ctx = await db.CreateDbContextAsync(CancellationToken.None);
        return await ctx.Artifacts.SingleOrDefaultAsync(a => a.Id == artifactId, CancellationToken.None);
    }

    [Fact]
    public async Task CreateForConsoleUploadAsync_OwnerMismatch_ThrowsUnauthorized()
    {
        var f = await SetupAsync();
        var request = new CreateArtifactRequest(f.SessionId, "foo.txt", 10, null, ArtifactOrigin.Console);

        var act = () => f.Artifacts.CreateForConsoleUploadAsync("intruder", request, CancellationToken.None);

        await act.Should().ThrowAsync<UnauthorizedAccessException>();
    }

    [Fact]
    public async Task CreateForConsoleUploadAsync_InvalidFilename_ThrowsArgument()
    {
        var f = await SetupAsync();
        var request = new CreateArtifactRequest(f.SessionId, "../escape.txt", 10, null, ArtifactOrigin.Console);

        var act = () => f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, request, CancellationToken.None);

        await act.Should().ThrowAsync<ArgumentException>();
    }

    [Fact]
    public async Task CreateForConsoleUploadAsync_SizeCapExceeded_Throws()
    {
        var opts = new ArtifactStorageOptions { MaxArtifactSizeBytes = 100 };
        var f = await SetupAsync(options: opts);
        var request = new CreateArtifactRequest(f.SessionId, "foo.txt", 101, null, ArtifactOrigin.Console);

        var act = () => f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, request, CancellationToken.None);

        await act.Should().ThrowAsync<ArgumentException>();
    }

    [Fact]
    public async Task CreateForConsoleUploadAsync_ExceedsSessionArtifactLimit_Throws()
    {
        var opts = new ArtifactStorageOptions { MaxArtifactsPerSession = 1 };
        var f = await SetupAsync(options: opts);
        await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "first.txt", 4, null, ArtifactOrigin.Console), CancellationToken.None);
        var second = new CreateArtifactRequest(f.SessionId, "second.txt", 4, null, ArtifactOrigin.Console);

        var act = () => f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, second, CancellationToken.None);

        await act.Should().ThrowAsync<InvalidOperationException>().WithMessage("*quota*");
        f.Storage.UploadUrlCalls.Should().Be(1);
    }

    [Fact]
    public async Task CreateForConsoleUploadAsync_DuplicateFilename_Throws()
    {
        var f = await SetupAsync();
        await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "dup.txt", 4, null, ArtifactOrigin.Console), CancellationToken.None);
        var duplicate = new CreateArtifactRequest(f.SessionId, "dup.txt", 6, null, ArtifactOrigin.Console);

        var act = () => f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, duplicate, CancellationToken.None);

        await act.Should().ThrowAsync<InvalidOperationException>().WithMessage("*Duplicate*");
    }

    [Fact]
    public async Task CreateForConsoleUploadAsync_ValidRequest_InsertsPendingRowAndReturnsUrl()
    {
        var opts = new ArtifactStorageOptions { MaxArtifactSizeBytes = 50 * 1024 * 1024, MaxArtifactAgeDays = 7 };
        var f = await SetupAsync(options: opts);
        var request = new CreateArtifactRequest(f.SessionId, "log.txt", 12, "deadbeef", ArtifactOrigin.Console);

        var resp = await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, request, CancellationToken.None);

        resp.UploadUrl.Should().StartWith("https://fake-s3.local/");
        resp.ArtifactId.Should().NotBeEmpty();
        resp.ExpiresAt.Should().BeCloseTo(DateTimeOffset.UtcNow.AddDays(7), TimeSpan.FromSeconds(5));
        f.Storage.UploadUrlCalls.Should().Be(1);

        var entity = await GetArtifactAsync(f.Db, f.SessionId, "log.txt");
        entity.Status.Should().Be(ArtifactStatus.Pending);
        entity.Origin.Should().Be(ArtifactOrigin.Console);
        entity.OwnerUserId.Should().Be(f.OwnerId);
        entity.SizeBytes.Should().Be(12);
        entity.FileCategory.Should().Be(ArtifactFileCategory.Text);
        entity.ExpiresAtUtc.Should().BeCloseTo(DateTimeOffset.UtcNow.AddDays(7), TimeSpan.FromSeconds(5));
    }

    [Fact]
    public async Task CompleteConsoleUploadAsync_OwnerMismatch_ThrowsUnauthorized()
    {
        var f = await SetupAsync();
        var artifactId = (await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "foo.txt", 4, null, ArtifactOrigin.Console), CancellationToken.None)).ArtifactId;

        var act = () => f.Artifacts.CompleteConsoleUploadAsync("intruder", artifactId, "cafe", CancellationToken.None);

        await act.Should().ThrowAsync<UnauthorizedAccessException>();
    }

    [Fact]
    public async Task CompleteConsoleUploadAsync_ObjectMissingFromStorage_Throws()
    {
        var f = await SetupAsync();
        var artifactId = (await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "foo.txt", 4, null, ArtifactOrigin.Console), CancellationToken.None)).ArtifactId;

        var act = () => f.Artifacts.CompleteConsoleUploadAsync(f.OwnerId, artifactId, "sha", CancellationToken.None);

        await act.Should().ThrowAsync<InvalidOperationException>().WithMessage("*missing*");
    }

    [Fact]
    public async Task CompleteConsoleUploadAsync_SizeMismatch_DeletesObjectAndThrows()
    {
        var f = await SetupAsync();
        var createResp = await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "foo.txt", 10, null, ArtifactOrigin.Console), CancellationToken.None);
        f.Storage.Seed(f.SessionId, "foo.txt", new byte[10]);
        f.Storage.OverrideSize(f.SessionId, "foo.txt", 99);

        var act = () => f.Artifacts.CompleteConsoleUploadAsync(f.OwnerId, createResp.ArtifactId, "sha", CancellationToken.None);

        await act.Should().ThrowAsync<InvalidOperationException>().WithMessage("*Size*");
        f.Storage.DeleteObjectCalls.Should().Be(1);
        f.Hub.Users[f.OwnerId].Invocations.Should().BeEmpty();
        (await FindArtifactAsync(f.Db, createResp.ArtifactId)).Should().BeNull();
    }

    [Fact]
    public async Task CompleteConsoleUploadAsync_ReadyStatus_FlipsToReadyAndBroadcasts()
    {
        var f = await SetupAsync();
        var createResp = await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "log.txt", 12, null, ArtifactOrigin.Console), CancellationToken.None);
        f.Storage.Seed(f.SessionId, "log.txt", new byte[12]);

        await f.Artifacts.CompleteConsoleUploadAsync(f.OwnerId, createResp.ArtifactId, "deadbeef", CancellationToken.None);

        var entity = await GetArtifactAsync(f.Db, f.SessionId, "log.txt");
        entity.Status.Should().Be(ArtifactStatus.Ready);
        entity.ContentSha256.Should().Be("deadbeef");
        entity.CompletedAtUtc.Should().NotBeNull();

        var userProxy = f.Hub.Users[f.OwnerId];
        userProxy.Invocations.Should().ContainSingle(i => i.Method == "ArtifactChanged");
        var broadcast = (ArtifactChangedEvent)userProxy.Invocations.Single(i => i.Method == "ArtifactChanged").Arguments[0]!;
        broadcast.ChangeType.Should().Be(ArtifactChangeType.Created);
        broadcast.Artifact!.Filename.Should().Be("log.txt");

        f.Dispatcher.Notifications.Should().ContainSingle();
        f.Dispatcher.Notifications[0].WorkerConnectionId.Should().Be(f.WorkerConnId);
        f.Dispatcher.Notifications[0].Frame.SessionId.Should().Be(f.SessionId);
        f.Dispatcher.Notifications[0].Frame.Filename.Should().Be("log.txt");
        f.Dispatcher.Notifications[0].Frame.DownloadUrl.Should().StartWith("https://fake-s3.local/");
    }

    [Fact]
    public async Task CompleteConsoleUploadAsync_AlreadyComplete_Throws()
    {
        var f = await SetupAsync();
        var createResp = await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "log.txt", 8, null, ArtifactOrigin.Console), CancellationToken.None);
        f.Storage.Seed(f.SessionId, "log.txt", new byte[8]);
        await f.Artifacts.CompleteConsoleUploadAsync(f.OwnerId, createResp.ArtifactId, "sha", CancellationToken.None);

        var act = () => f.Artifacts.CompleteConsoleUploadAsync(f.OwnerId, createResp.ArtifactId, "sha", CancellationToken.None);

        await act.Should().ThrowAsync<InvalidOperationException>().WithMessage("*not pending*");
    }

    [Fact]
    public async Task CreateForWorkerUploadAsync_NewFile_InsertsPendingRow()
    {
        var f = await SetupAsync();
        var request = new CreateArtifactRequest(f.SessionId, "worker.txt", 20, "aaa", ArtifactOrigin.Worker);

        var resp = await f.Artifacts.CreateForWorkerUploadAsync(f.WorkerConnId, f.OwnerId, request, CancellationToken.None);

        resp.UploadUrl.Should().NotBeEmpty();
        var entity = await GetArtifactAsync(f.Db, f.SessionId, "worker.txt");
        entity.Status.Should().Be(ArtifactStatus.Pending);
        entity.Origin.Should().Be(ArtifactOrigin.Worker);
        entity.OwnerUserId.Should().Be(f.OwnerId);
        entity.SizeBytes.Should().Be(20);
        entity.ContentSha256.Should().Be("aaa");
        f.Storage.UploadUrlCalls.Should().Be(1);
    }

    [Fact]
    public async Task CreateForWorkerUploadAsync_WrongWorkerConnection_Throws()
    {
        var f = await SetupAsync();
        var request = new CreateArtifactRequest(f.SessionId, "worker.txt", 20, null, ArtifactOrigin.Worker);

        var act = () => f.Artifacts.CreateForWorkerUploadAsync("intruder-conn", f.OwnerId, request, CancellationToken.None);

        await act.Should().ThrowAsync<UnauthorizedAccessException>();
    }

    [Fact]
    public async Task CreateForWorkerUploadAsync_ExistingPendingRow_ReusesRow()
    {
        var f = await SetupAsync();
        var first = await f.Artifacts.CreateForWorkerUploadAsync(f.WorkerConnId, f.OwnerId, new CreateArtifactRequest(f.SessionId, "worker.txt", 20, "sha1", ArtifactOrigin.Worker), CancellationToken.None);
        var second = await f.Artifacts.CreateForWorkerUploadAsync(f.WorkerConnId, f.OwnerId, new CreateArtifactRequest(f.SessionId, "worker.txt", 22, "sha2", ArtifactOrigin.Worker), CancellationToken.None);

        first.ArtifactId.Should().Be(second.ArtifactId);
        var entity = await GetArtifactAsync(f.Db, f.SessionId, "worker.txt");
        entity.SizeBytes.Should().Be(22);
        entity.ContentSha256.Should().Be("sha2");
    }

    [Fact]
    public async Task CreateForWorkerUploadAsync_ExistingReadyRow_ResetsToPending()
    {
        var f = await SetupAsync();
        var first = await f.Artifacts.CreateForWorkerUploadAsync(f.WorkerConnId, f.OwnerId, new CreateArtifactRequest(f.SessionId, "worker.txt", 20, "sha1", ArtifactOrigin.Worker), CancellationToken.None);
        f.Storage.Seed(f.SessionId, "worker.txt", new byte[20]);
        await f.Artifacts.CompleteWorkerUploadAsync(f.WorkerConnId, f.OwnerId, first.ArtifactId, "sha1", CancellationToken.None);

        var entityBefore = await GetArtifactAsync(f.Db, f.SessionId, "worker.txt");
        entityBefore.Status.Should().Be(ArtifactStatus.Ready);

        var second = await f.Artifacts.CreateForWorkerUploadAsync(f.WorkerConnId, f.OwnerId, new CreateArtifactRequest(f.SessionId, "worker.txt", 30, "sha2", ArtifactOrigin.Worker), CancellationToken.None);

        first.ArtifactId.Should().Be(second.ArtifactId);
        var entityAfter = await GetArtifactAsync(f.Db, f.SessionId, "worker.txt");
        entityAfter.Status.Should().Be(ArtifactStatus.Pending);
        entityAfter.SizeBytes.Should().Be(30);
        entityAfter.ContentSha256.Should().Be("sha2");
    }

    [Fact]
    public async Task ListAsync_FiltersBySessionId_ReturnsSortedByUploadedAtAsc()
    {
        var f = await SetupAsync();
        var older = await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "older.txt", 4, null, ArtifactOrigin.Console), CancellationToken.None);
        f.Storage.Seed(f.SessionId, "older.txt", new byte[4]);
        await f.Artifacts.CompleteConsoleUploadAsync(f.OwnerId, older.ArtifactId, "sha-old", CancellationToken.None);

        await Task.Delay(20);
        var newer = await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "newer.txt", 4, null, ArtifactOrigin.Console), CancellationToken.None);
        f.Storage.Seed(f.SessionId, "newer.txt", new byte[4]);
        await f.Artifacts.CompleteConsoleUploadAsync(f.OwnerId, newer.ArtifactId, "sha-new", CancellationToken.None);

        var list = await f.Artifacts.ListAsync(f.OwnerId, f.SessionId, CancellationToken.None);

        list.Should().HaveCount(2);
        list[0].Filename.Should().Be("older.txt");
        list[1].Filename.Should().Be("newer.txt");
    }

    [Fact]
    public async Task CreateForWorkerUpload_NewArtifact_SetsExpiresAtToTtlEnd()
    {
        var f = await SetupAsync();
        var before = DateTimeOffset.UtcNow;

        var upload = await f.Artifacts.CreateForWorkerUploadAsync(
            f.WorkerConnId, f.OwnerId,
            new CreateArtifactRequest(f.SessionId, "worker.txt", 4, null, ArtifactOrigin.Worker),
            CancellationToken.None);

        await using var db = await f.Db.CreateDbContextAsync(CancellationToken.None);
        var entity = await db.Artifacts.SingleAsync(a => a.Id == upload.ArtifactId);
        entity.ExpiresAtUtc.Should().BeCloseTo(before.AddDays(7), TimeSpan.FromSeconds(10));
    }

    [Fact]
    public async Task CreateForWorkerUpload_ExistingArtifact_PreservesEarlierExpiresAt()
    {
        var f = await SetupAsync();
        var first = await f.Artifacts.CreateForWorkerUploadAsync(
            f.WorkerConnId, f.OwnerId,
            new CreateArtifactRequest(f.SessionId, "worker.txt", 4, null, ArtifactOrigin.Worker),
            CancellationToken.None);

        await Task.Delay(20);
        var second = await f.Artifacts.CreateForWorkerUploadAsync(
            f.WorkerConnId, f.OwnerId,
            new CreateArtifactRequest(f.SessionId, "worker.txt", 5, null, ArtifactOrigin.Worker),
            CancellationToken.None);

        second.ArtifactId.Should().Be(first.ArtifactId);
        await using var db = await f.Db.CreateDbContextAsync(CancellationToken.None);
        var entity = await db.Artifacts.SingleAsync(a => a.Id == first.ArtifactId);
        entity.ExpiresAtUtc.Should().BeCloseTo(first.ExpiresAt, TimeSpan.FromSeconds(5));
    }

    [Fact]
    public async Task ListAsync_OwnerMismatch_ThrowsUnauthorized()
    {
        var f = await SetupAsync();

        var act = () => f.Artifacts.ListAsync("intruder", f.SessionId, CancellationToken.None);

        await act.Should().ThrowAsync<UnauthorizedAccessException>();
    }

    [Fact]
    public async Task GetDownloadUrlAsync_PendingStatus_Throws()
    {
        var f = await SetupAsync();
        var createResp = await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "foo.txt", 4, null, ArtifactOrigin.Console), CancellationToken.None);

        var act = () => f.Artifacts.GetDownloadUrlAsync(f.OwnerId, createResp.ArtifactId, CancellationToken.None);

        await act.Should().ThrowAsync<InvalidOperationException>().WithMessage("*not ready*");
    }

    [Fact]
    public async Task GetDownloadUrlAsync_ReadyArtifact_ReturnsUrl()
    {
        var f = await SetupAsync();
        var createResp = await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "foo.txt", 4, null, ArtifactOrigin.Console), CancellationToken.None);
        f.Storage.Seed(f.SessionId, "foo.txt", new byte[4]);
        await f.Artifacts.CompleteConsoleUploadAsync(f.OwnerId, createResp.ArtifactId, "sha", CancellationToken.None);

        var download = await f.Artifacts.GetDownloadUrlAsync(f.OwnerId, createResp.ArtifactId, CancellationToken.None);

        download.DownloadUrl.Should().StartWith("https://fake-s3.local/");
        f.Storage.DownloadUrlCalls.Should().BeGreaterThanOrEqualTo(1);
    }

    [Fact]
    public async Task DeleteAsync_ReadyStatus_SoftDeletesAndBroadcasts()
    {
        var f = await SetupAsync();
        var createResp = await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "foo.txt", 4, null, ArtifactOrigin.Console), CancellationToken.None);
        f.Storage.Seed(f.SessionId, "foo.txt", new byte[4]);
        await f.Artifacts.CompleteConsoleUploadAsync(f.OwnerId, createResp.ArtifactId, "sha", CancellationToken.None);

        await f.Artifacts.DeleteAsync(f.OwnerId, createResp.ArtifactId, CancellationToken.None);

        var entity = await GetArtifactAsync(f.Db, f.SessionId, "foo.txt");
        entity.Status.Should().Be(ArtifactStatus.Deleted);
        f.Storage.DeleteObjectCalls.Should().Be(1);

        var deletes = f.Hub.Users[f.OwnerId].Invocations.Where(i => i.Method == "ArtifactChanged").ToList();
        deletes.Should().HaveCount(2);
        var last = (ArtifactChangedEvent)deletes[1].Arguments[0]!;
        last.ChangeType.Should().Be(ArtifactChangeType.Deleted);
        last.Artifact.Should().BeNull();
    }

    [Fact]
    public async Task DeleteAsync_OwnerMismatch_ThrowsUnauthorized()
    {
        var f = await SetupAsync();
        var createResp = await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "foo.txt", 4, null, ArtifactOrigin.Console), CancellationToken.None);

        var act = () => f.Artifacts.DeleteAsync("intruder", createResp.ArtifactId, CancellationToken.None);

        await act.Should().ThrowAsync<UnauthorizedAccessException>();
    }

    [Fact]
    public async Task DeleteByWorkerAsync_ExistingRow_SoftDeletesAndBroadcasts()
    {
        var f = await SetupAsync();
        var createResp = await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "foo.txt", 4, null, ArtifactOrigin.Console), CancellationToken.None);
        f.Storage.Seed(f.SessionId, "foo.txt", new byte[4]);
        await f.Artifacts.CompleteConsoleUploadAsync(f.OwnerId, createResp.ArtifactId, "sha", CancellationToken.None);

        await f.Artifacts.DeleteByWorkerAsync(f.SessionId, "foo.txt", CancellationToken.None);

        var entity = await GetArtifactAsync(f.Db, f.SessionId, "foo.txt");
        entity.Status.Should().Be(ArtifactStatus.Deleted);
        f.Storage.DeleteObjectCalls.Should().Be(1);
        var lastBroadcast = f.Hub.Users[f.OwnerId].Invocations
            .Where(i => i.Method == "ArtifactChanged")
            .Select(i => (ArtifactChangedEvent)i.Arguments[0]!)
            .Last();
        lastBroadcast.ChangeType.Should().Be(ArtifactChangeType.Deleted);
    }

    [Fact]
    public async Task DeleteByWorkerAsync_NoRow_DoesNothing()
    {
        var f = await SetupAsync();

        await f.Artifacts.DeleteByWorkerAsync(f.SessionId, "nonexistent.txt", CancellationToken.None);

        f.Storage.DeleteObjectCalls.Should().Be(0);
        f.Hub.Users.Values.SelectMany(p => p.Invocations).Should().BeEmpty();
    }

    [Fact]
    public async Task OnSessionTerminatedAsync_TightensExpiresAtToGracePeriod()
    {
        var opts = new ArtifactStorageOptions { MaxArtifactAgeDays = 7, GracePeriodHours = 24 };
        var f = await SetupAsync(options: opts);
        var createResp = await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "foo.txt", 4, null, ArtifactOrigin.Console), CancellationToken.None);
        f.Storage.Seed(f.SessionId, "foo.txt", new byte[4]);
        await f.Artifacts.CompleteConsoleUploadAsync(f.OwnerId, createResp.ArtifactId, "sha", CancellationToken.None);

        var before = (await GetArtifactAsync(f.Db, f.SessionId, "foo.txt")).ExpiresAtUtc;
        before.Should().BeCloseTo(DateTimeOffset.UtcNow.AddDays(7), TimeSpan.FromSeconds(10));

        await f.Artifacts.OnSessionTerminatedAsync(f.SessionId, CancellationToken.None);

        var after = (await GetArtifactAsync(f.Db, f.SessionId, "foo.txt")).ExpiresAtUtc;
        after.Should().BeCloseTo(DateTimeOffset.UtcNow.AddHours(24), TimeSpan.FromSeconds(10));
        var broadcasts = f.Hub.Users[f.OwnerId].Invocations.Where(i => i.Method == "ArtifactChanged").ToList();
        var last = (ArtifactChangedEvent)broadcasts.Last().Arguments[0]!;
        last.ChangeType.Should().Be(ArtifactChangeType.Updated);
    }

    [Fact]
    public async Task OnSessionTerminatedAsync_AlreadyShortExpiry_StaysUnchanged()
    {
        var opts = new ArtifactStorageOptions { MaxArtifactAgeDays = 7, GracePeriodHours = 24 };
        var f = await SetupAsync(options: opts);
        var createResp = await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "foo.txt", 4, null, ArtifactOrigin.Console), CancellationToken.None);

        await using (var ctx = await f.Db.CreateDbContextAsync(CancellationToken.None))
        {
            var row = await ctx.Artifacts.SingleAsync(a => a.Id == createResp.ArtifactId, CancellationToken.None);
            row.ExpiresAtUtc = DateTimeOffset.UtcNow.AddHours(1);
            await ctx.SaveChangesAsync(CancellationToken.None);
        }

        await f.Artifacts.OnSessionTerminatedAsync(f.SessionId, CancellationToken.None);

        await using (var ctx = await f.Db.CreateDbContextAsync(CancellationToken.None))
        {
            var row = await ctx.Artifacts.SingleAsync(a => a.Id == createResp.ArtifactId, CancellationToken.None);
            row.ExpiresAtUtc.Should().BeCloseTo(DateTimeOffset.UtcNow.AddHours(1), TimeSpan.FromSeconds(5));
        }

        f.Hub.Users[f.OwnerId].Invocations.Should().BeEmpty();
    }

    [Fact]
    public async Task CleanExpiredAsync_PastExpiresAt_DeletesObjectAndDbRow_Broadcasts()
    {
        var f = await SetupAsync();
        var createResp = await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "foo.txt", 4, null, ArtifactOrigin.Console), CancellationToken.None);
        f.Storage.Seed(f.SessionId, "foo.txt", new byte[4]);
        await f.Artifacts.CompleteConsoleUploadAsync(f.OwnerId, createResp.ArtifactId, "sha", CancellationToken.None);

        await using (var ctx = await f.Db.CreateDbContextAsync(CancellationToken.None))
        {
            var row = await ctx.Artifacts.SingleAsync(a => a.Id == createResp.ArtifactId, CancellationToken.None);
            row.ExpiresAtUtc = DateTimeOffset.UtcNow.AddHours(-1);
            await ctx.SaveChangesAsync(CancellationToken.None);
        }

        var count = await f.Artifacts.CleanExpiredAsync(CancellationToken.None);

        count.Should().Be(1);
        f.Storage.DeleteObjectCalls.Should().Be(1);
        f.Storage.ObjectExists(f.SessionId, "foo.txt").Should().BeFalse();
        var last = (ArtifactChangedEvent)f.Hub.Users[f.OwnerId].Invocations
            .Where(i => i.Method == "ArtifactChanged")
            .Select(i => (ArtifactChangedEvent)i.Arguments[0]!)
            .Last();
        last.ChangeType.Should().Be(ArtifactChangeType.Deleted);

        var entity = await FindArtifactAsync(f.Db, createResp.ArtifactId);
        entity!.Status.Should().Be(ArtifactStatus.Deleted);

        var audit = f.AuditLog.Entries.Single(a => a.TargetId == createResp.ArtifactId && a.Action == "artifact.cleanupExpired");
        audit.UserId.Should().Be("system");
    }

    [Fact]
    public async Task CleanExpiredAsync_NotYetExpired_DoesNothing()
    {
        var f = await SetupAsync();
        await f.Artifacts.CreateForConsoleUploadAsync(f.OwnerId, new CreateArtifactRequest(f.SessionId, "foo.txt", 4, null, ArtifactOrigin.Console), CancellationToken.None);

        var count = await f.Artifacts.CleanExpiredAsync(CancellationToken.None);

        count.Should().Be(0);
        f.Storage.DeleteObjectCalls.Should().Be(0);
        f.Hub.Users[f.OwnerId].Invocations.Should().BeEmpty();
    }
}
