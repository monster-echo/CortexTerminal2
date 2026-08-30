using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Gateway.RemoteFiles;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.RemoteFiles;

public sealed class PendingTransferRegistryTests
{
    private static PendingTransfer NewTransfer(
        string id, string userId = "user-1", string status = FileTransferStatus.Pending,
        DateTimeOffset? createdAt = null, FileOperationError? error = null)
        => new(
            RequestId: id,
            SessionId: "sess-1",
            UserId: userId,
            WorkerConnectionId: "worker-conn-1",
            TargetPath: "docs",
            Filename: "note.txt",
            SizeBytes: 10,
            Sha256: "abc",
            Status: status,
            Error: error,
            CreatedAtUtc: createdAt ?? DateTimeOffset.UtcNow);

    [Fact]
    public void GetOwned_ReturnsOwnTransfer()
    {
        var registry = new PendingTransferRegistry();
        registry.Upsert(NewTransfer("t1"));

        var act = () => registry.GetOwned("t1", "user-1");

        act.Should().NotThrow();
    }

    [Theory]
    [InlineData("missing")]
    [InlineData("t1")]
    public void GetOwned_MissingOrForeign_ThrowsTransferNotFound(string requestedId)
    {
        var registry = new PendingTransferRegistry();
        registry.Upsert(NewTransfer("t1", userId: "user-1"));

        var act = () => registry.GetOwned(requestedId, requestedId == "t1" ? "user-2" : "user-1");

        act.Should().Throw<RemoteFileServiceException>()
            .Which.Code.Should().Be(FileTransferErrorCode.TransferNotFound);
    }

    [Fact]
    public void TryUpdate_FlipsStatus()
    {
        var registry = new PendingTransferRegistry();
        registry.Upsert(NewTransfer("t1"));

        var updated = registry.TryUpdate("t1", t => t with { Status = FileTransferStatus.Ready });

        updated.Should().BeTrue();
        registry.GetOwned("t1", "user-1").Status.Should().Be(FileTransferStatus.Ready);
    }

    [Fact]
    public void SweepExpired_TimesOutStalePending()
    {
        var registry = new PendingTransferRegistry();
        registry.Upsert(NewTransfer("stale", createdAt: DateTimeOffset.UtcNow.AddMinutes(-20)));
        registry.Upsert(NewTransfer("fresh"));

        var changed = registry.SweepExpired(TimeSpan.FromMinutes(15));

        changed.Should().Be(1);
        var stale = registry.GetOwned("stale", "user-1");
        stale.Status.Should().Be(FileTransferStatus.Failed);
        stale.Error!.Code.Should().Be(FileTransferErrorCode.Timeout);
        registry.GetOwned("fresh", "user-1").Status.Should().Be(FileTransferStatus.Pending);
    }

    [Fact]
    public void SweepExpired_RemovesAgedTerminalEntries()
    {
        var registry = new PendingTransferRegistry();
        registry.Upsert(NewTransfer("old-ready", createdAt: DateTimeOffset.UtcNow.AddMinutes(-20)));
        registry.TryUpdate("old-ready", t => t with
        {
            Status = FileTransferStatus.Ready,
            TerminalAtUtc = DateTimeOffset.UtcNow.AddMinutes(-20)
        });
        registry.Upsert(NewTransfer("recent-ready"));
        registry.TryUpdate("recent-ready", t => t with
        {
            Status = FileTransferStatus.Ready,
            TerminalAtUtc = DateTimeOffset.UtcNow
        });

        var changed = registry.SweepExpired(TimeSpan.FromMinutes(15));

        changed.Should().Be(1);
        var act = () => registry.GetOwned("old-ready", "user-1");
        act.Should().Throw<RemoteFileServiceException>();
        registry.GetOwned("recent-ready", "user-1").Status.Should().Be(FileTransferStatus.Ready);
    }
}
