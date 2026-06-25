using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Sessions;
using CortexTerminal.Gateway.Tests.Sessions.Fakes;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Sessions;

public sealed class ArtifactCleanupHostedServiceTests
{
    private static async Task<(ArtifactService artifacts, IDbContextFactory<AppDbContext> db, FakeArtifactStorage storage, string sessionId, string artifactId)> SetupWithExpiredArtifactAsync()
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1", ownerUserId: "user-1");
        var storage = new FakeArtifactStorage();
        var hub = new ArtifactTestHubContext("user-1");
        var dispatcher = new RecordingArtifactCommandDispatcher();
        var (db, sessions, artifacts) = TestSessionFactory.CreateArtifactService(workers, storage, hub, dispatcher);
        var create = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);
        var sessionId = create.Response!.SessionId;
        var createResp = await artifacts.CreateForConsoleUploadAsync("user-1", new CreateArtifactRequest(sessionId, "foo.txt", 4, null, ArtifactOrigin.Console), CancellationToken.None);
        storage.Seed(sessionId, "foo.txt", new byte[4]);
        await artifacts.CompleteConsoleUploadAsync("user-1", createResp.ArtifactId, "sha", CancellationToken.None);

        await using (var ctx = await db.CreateDbContextAsync(CancellationToken.None))
        {
            var row = await ctx.Artifacts.SingleAsync(a => a.Id == createResp.ArtifactId, CancellationToken.None);
            row.ExpiresAtUtc = DateTimeOffset.UtcNow.AddHours(-1);
            await ctx.SaveChangesAsync(CancellationToken.None);
        }
        return (artifacts, db, storage, sessionId, createResp.ArtifactId);
    }

    [Fact]
    public async Task StartAsync_RunsInitialSweepImmediately()
    {
        var (artifacts, db, storage, sessionId, artifactId) = await SetupWithExpiredArtifactAsync();
        var svc = new ArtifactCleanupHostedService(artifacts, TimeProvider.System, NullLogger<ArtifactCleanupHostedService>.Instance);
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));

        await svc.StartAsync(cts.Token);

        // BackgroundService.ExecuteAsync runs the first sweep synchronously before the first
        // Task.Delay, but the task is observed as "running". Poll until the sweep lands.
        var deadline = DateTimeOffset.UtcNow.AddSeconds(3);
        string status = ArtifactStatus.Ready;
        while (DateTimeOffset.UtcNow < deadline)
        {
            await using var ctx = await db.CreateDbContextAsync(CancellationToken.None);
            var row = await ctx.Artifacts.AsNoTracking().SingleAsync(a => a.Id == artifactId, CancellationToken.None);
            status = row.Status;
            if (status == ArtifactStatus.Deleted) break;
            await Task.Delay(50);
        }

        status.Should().Be(ArtifactStatus.Deleted);
        storage.DeleteObjectCalls.Should().Be(1);

        await svc.StopAsync(CancellationToken.None);
    }

    [Fact]
    public async Task StartAsync_NoExpiredArtifacts_SweepIsNoOp()
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1", ownerUserId: "user-1");
        var storage = new FakeArtifactStorage();
        var hub = new ArtifactTestHubContext("user-1");
        var dispatcher = new RecordingArtifactCommandDispatcher();
        var (_, sessions, artifacts) = TestSessionFactory.CreateArtifactService(workers, storage, hub, dispatcher);
        _ = await sessions.CreateSessionAsync("user-1", new CreateSessionRequest("shell", 120, 40), clientConnectionId: null, CancellationToken.None);

        var svc = new ArtifactCleanupHostedService(artifacts, TimeProvider.System, NullLogger<ArtifactCleanupHostedService>.Instance);
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));

        await svc.StartAsync(cts.Token);
        storage.DeleteObjectCalls.Should().Be(0);
        await svc.StopAsync(CancellationToken.None);
    }

    [Fact]
    public async Task StopAsync_WithoutStart_IsIdempotent()
    {
        var workers = TestSessionFactory.CreateWorkerRegistry();
        workers.Register("worker-1", "worker-conn-1", ownerUserId: "user-1");
        var storage = new FakeArtifactStorage();
        var hub = new ArtifactTestHubContext("user-1");
        var dispatcher = new RecordingArtifactCommandDispatcher();
        var (_, sessions, artifacts) = TestSessionFactory.CreateArtifactService(workers, storage, hub, dispatcher);
        var svc = new ArtifactCleanupHostedService(artifacts, TimeProvider.System, NullLogger<ArtifactCleanupHostedService>.Instance);

        var act = () => svc.StopAsync(CancellationToken.None);

        await act.Should().NotThrowAsync();
    }

    [Fact]
    public async Task StopAsync_CancelsRunningLoopCleanly()
    {
        var (artifacts, _, _, _, _) = await SetupWithExpiredArtifactAsync();
        var svc = new ArtifactCleanupHostedService(artifacts, TimeProvider.System, NullLogger<ArtifactCleanupHostedService>.Instance);
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));
        await svc.StartAsync(cts.Token);

        await svc.StopAsync(CancellationToken.None);

        // Service should accept StopAsync without throwing and allow instance to be collected.
        svc.Dispose();
    }
}
