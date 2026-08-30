using System.Collections.Concurrent;
using CortexTerminal.Contracts.Sessions;

namespace CortexTerminal.Gateway.RemoteFiles;

/// <summary>
/// One in-memory transfer record. Status moves pending → ready (success) or pending →
/// failed; <see cref="TerminalAtUtc"/> is stamped on every terminal transition so the
/// sweeper can age terminal states out on the same clock.
/// </summary>
public sealed record PendingTransfer(
    string RequestId,
    string SessionId,
    string UserId,
    string WorkerConnectionId,
    string TargetPath,
    string? Filename,
    long SizeBytes,
    string? Sha256,
    string Status,
    FileOperationError? Error,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? TerminalAtUtc = null);

/// <summary>
/// In-process registry of remote-file transfers, keyed by requestId. Deliberately not
/// persisted: a transfer is a short-lived S3 transit, and a gateway restart simply 404s
/// the phone's poll, which surfaces as a retryable error. Requires LB session affinity —
/// the same property SignalR already depends on (there is no backplane).
/// </summary>
public sealed class PendingTransferRegistry
{
    private readonly ConcurrentDictionary<string, PendingTransfer> _transfers = new();

    public void Upsert(PendingTransfer transfer)
        => _transfers[transfer.RequestId] = transfer;

    /// <summary>
    /// Fetch a transfer and assert it belongs to <paramref name="userId"/>. Unknown ids and
    /// other users' ids are both reported as TransferNotFound — no oracle for probing.
    /// </summary>
    public PendingTransfer GetOwned(string requestId, string userId)
    {
        if (!_transfers.TryGetValue(requestId, out var transfer) || transfer.UserId != userId)
        {
            throw new RemoteFileServiceException(FileTransferErrorCode.TransferNotFound, "no such transfer");
        }
        return transfer;
    }

    public bool TryUpdate(string requestId, Func<PendingTransfer, PendingTransfer> update)
    {
        while (true)
        {
            if (!_transfers.TryGetValue(requestId, out var current)) return false;
            if (_transfers.TryUpdate(requestId, update(current), current)) return true;
        }
    }

    public bool Remove(string requestId) => _transfers.TryRemove(requestId, out _);

    /// <summary>
    /// Age out entries: pending transfers past the TTL become failed("timeout") so the
    /// phone's poll sees a terminal state; terminal entries past the TTL are removed.
    /// Returns the number of entries changed or removed.
    /// </summary>
    public int SweepExpired(TimeSpan ttl)
    {
        var now = DateTimeOffset.UtcNow;
        var changed = 0;

        foreach (var (id, transfer) in _transfers)
        {
            if (transfer.Status == FileTransferStatus.Pending)
            {
                if (now - transfer.CreatedAtUtc > ttl)
                {
                    var failed = transfer with
                    {
                        Status = FileTransferStatus.Failed,
                        Error = new FileOperationError(FileTransferErrorCode.Timeout, "transfer timed out"),
                        TerminalAtUtc = now,
                    };
                    if (TryUpdate(id, _ => failed)) changed++;
                }
                continue;
            }

            var terminalAt = transfer.TerminalAtUtc ?? transfer.CreatedAtUtc;
            if (now - terminalAt > ttl && _transfers.TryRemove(id, out _))
            {
                changed++;
            }
        }

        return changed;
    }
}
