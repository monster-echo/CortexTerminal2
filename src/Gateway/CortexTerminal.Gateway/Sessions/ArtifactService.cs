using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Gateway.Audit;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Hubs;
using CortexTerminal.Gateway.Storage;
using CortexTerminal.Gateway.WebSockets;
using CortexTerminal.Gateway.Workers;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace CortexTerminal.Gateway.Sessions;

/// <summary>
/// Orchestrates the artifact lifecycle: ownership checks, DB state machine, S3 storage
/// brokering, TTL bookkeeping, audit logging, and SignalR/WS fan-out to every connection
/// owned by the artifact's user.
/// </summary>
public sealed class ArtifactService(
    IDbContextFactory<AppDbContext> dbFactory,
    IArtifactStorage storage,
    ISessionCoordinator sessions,
    IAuditLogStore auditLog,
    IHubContext<TerminalHub> terminalHub,
    IArtifactCommandDispatcher workerCommands,
    IOptions<ArtifactStorageOptions> options,
    ILogger<ArtifactService> logger)
{
    private readonly ArtifactStorageOptions _options = options.Value;

    private static readonly HashSet<string> ValidOrigins = new(StringComparer.OrdinalIgnoreCase)
    {
        ArtifactOrigin.Console, ArtifactOrigin.Worker
    };

    /// <summary>
    /// Step 1 of the Console upload flow. Validates request, checks ownership and quotas,
    /// INSERTs a Pending artifact row, and returns a presigned PUT URL the client uses to
    /// upload directly to S3.
    /// </summary>
    public async Task<UploadUrlResponse> CreateForConsoleUploadAsync(string userId, CreateArtifactRequest request, CancellationToken ct)
    {
        if (!ValidOrigins.Contains(request.Origin)) throw new ArgumentException($"Invalid origin: {request.Origin}");
        if (!ArtifactFilenameValidator.IsValid(request.Filename)) throw new ArgumentException("Invalid filename");
        if (request.SizeBytes <= 0 || request.SizeBytes > _options.MaxArtifactSizeBytes)
            throw new ArgumentException($"Size must be between 1 and {_options.MaxArtifactSizeBytes} bytes");

        await using var db = await dbFactory.CreateDbContextAsync(ct);
        EnsureSessionOwnedByUser(request.SessionId, userId);
        await EnsureSessionQuotaAvailableAsync(db, request.SessionId, ct);

        // Console uploads reject duplicate filenames (409 contract). Worker uploads use last-write-wins.
        if (await db.Artifacts.AnyAsync(a => a.SessionId == request.SessionId && a.Filename == request.Filename, ct))
        {
            throw new InvalidOperationException("Duplicate filename");
        }

        var now = DateTimeOffset.UtcNow;
        var expiresAt = ComputeExpiresAt(now, sessionTerminated: false, existing: null);
        var entity = new ArtifactEntity
        {
            Id = Guid.NewGuid().ToString("N"),
            SessionId = request.SessionId,
            Filename = request.Filename,
            SizeBytes = request.SizeBytes,
            Status = ArtifactStatus.Pending,
            Origin = ArtifactOrigin.Console,
            OwnerUserId = userId,
            ContentSha256 = request.ContentSha256,
            FileCategory = FileCategoryDetector.Detect(request.Filename),
            CreatedAtUtc = now,
            ExpiresAtUtc = expiresAt
        };
        db.Artifacts.Add(entity);
        await db.SaveChangesAsync(ct);

        var upload = await storage.GenerateUploadUrlAsync(request.SessionId, request.Filename, ct);
        RecordAudit(userId, "artifact.create", entity.Id);
        logger.LogInformation("Artifact {ArtifactId} created (session {SessionId}, filename {Filename}, size {Size}).",
            entity.Id, entity.SessionId, entity.Filename, entity.SizeBytes);
        return upload with { ExpiresAt = expiresAt, ArtifactId = entity.Id };
    }

    /// <summary>
    /// Step 2 of the Console upload flow. Client calls this after a successful PUT to S3.
    /// Gateway verifies the object is present in S3, flips status to Ready, fans out an
    /// ArtifactChanged(created) event, and tells the owning Worker to mirror the file locally.
    /// </summary>
    public async Task CompleteConsoleUploadAsync(string userId, string artifactId, string contentSha256, CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var entity = await db.Artifacts.SingleOrDefaultAsync(a => a.Id == artifactId, ct)
            ?? throw new InvalidOperationException("Artifact not found");
        if (entity.OwnerUserId != userId) throw new UnauthorizedAccessException("Artifact belongs to another user");
        if (entity.Status != ArtifactStatus.Pending) throw new InvalidOperationException($"Artifact not pending: {entity.Status}");

        if (!await storage.ObjectExistsAsync(entity.SessionId, entity.Filename, ct))
            throw new InvalidOperationException("Object missing from storage");

        var actualSize = await storage.GetObjectSizeAsync(entity.SessionId, entity.Filename, ct);
        if (actualSize != entity.SizeBytes)
        {
            await storage.DeleteObjectAsync(entity.SessionId, entity.Filename, ct);
            db.Artifacts.Remove(entity);
            await db.SaveChangesAsync(ct);
            throw new InvalidOperationException($"Size mismatch: expected {entity.SizeBytes}, actual {actualSize}");
        }

        entity.Status = ArtifactStatus.Ready;
        entity.CompletedAtUtc = DateTimeOffset.UtcNow;
        entity.ContentSha256 = contentSha256;
        await db.SaveChangesAsync(ct);

        RecordAudit(userId, "artifact.complete", entity.Id);
        logger.LogInformation("Artifact {ArtifactId} upload complete; notifying worker.", entity.Id);

        await BroadcastArtifactChangeAsync(entity, ArtifactChangeType.Created, ct);
        await NotifyWorkerToMirrorAsync(entity, ct);
    }

    /// <summary>
    /// Worker-side create path used by the FileSystemWatcher pipeline. Re-uses the same
    /// Pending → Ready state machine but the entity is created with Origin=Worker and
    /// last-write-wins semantics: an existing Pending row for the same (sessionId, filename)
    /// is reused, while a Ready row is overwritten (status reset to Pending).
    /// </summary>
    public async Task<UploadUrlResponse> CreateForWorkerUploadAsync(string workerConnectionId, string workerOwnerUserId, CreateArtifactRequest request, CancellationToken ct)
    {
        if (!ArtifactFilenameValidator.IsValid(request.Filename)) throw new ArgumentException("Invalid filename");
        if (request.SizeBytes <= 0 || request.SizeBytes > _options.MaxArtifactSizeBytes)
            throw new ArgumentException($"Size must be between 1 and {_options.MaxArtifactSizeBytes} bytes");

        await using var db = await dbFactory.CreateDbContextAsync(ct);
        EnsureSessionOwnedByWorker(request.SessionId, workerConnectionId, workerOwnerUserId);

        var existing = await db.Artifacts.SingleOrDefaultAsync(a => a.SessionId == request.SessionId && a.Filename == request.Filename, ct);
        ArtifactEntity? loadedFromDb = null;
        if (existing is null)
        {
            await EnsureSessionQuotaAvailableAsync(db, request.SessionId, ct);
            existing = new ArtifactEntity
            {
                Id = Guid.NewGuid().ToString("N"),
                SessionId = request.SessionId,
                Filename = request.Filename,
                Origin = ArtifactOrigin.Worker,
                OwnerUserId = workerOwnerUserId,
                FileCategory = FileCategoryDetector.Detect(request.Filename),
                CreatedAtUtc = DateTimeOffset.UtcNow
            };
            db.Artifacts.Add(existing);
        }
        else
        {
            loadedFromDb = existing;
            if (existing.Status == ArtifactStatus.Deleted)
            {
                existing.CreatedAtUtc = DateTimeOffset.UtcNow;
            }
        }
        existing.SizeBytes = request.SizeBytes;
        existing.Status = ArtifactStatus.Pending;
        existing.ContentSha256 = request.ContentSha256;
        existing.ExpiresAtUtc = ComputeExpiresAt(DateTimeOffset.UtcNow, sessionTerminated: false, loadedFromDb);
        await db.SaveChangesAsync(ct);

        var upload = await storage.GenerateUploadUrlAsync(request.SessionId, request.Filename, ct);
        RecordAudit(workerOwnerUserId, "artifact.workerCreate", existing.Id);
        logger.LogInformation("Worker artifact {ArtifactId} created (session {SessionId}, filename {Filename}).",
            existing.Id, existing.SessionId, existing.Filename);
        return upload with { ExpiresAt = existing.ExpiresAtUtc, ArtifactId = existing.Id };
    }

    /// <summary>
    /// Worker-side complete path. Mirrors <see cref="CompleteConsoleUploadAsync"/> but triggered by
    /// the Worker after its HttpClient PUT to S3 finishes.
    /// </summary>
    public async Task CompleteWorkerUploadAsync(string workerConnectionId, string workerOwnerUserId, string artifactId, string contentSha256, CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var entity = await db.Artifacts.SingleOrDefaultAsync(a => a.Id == artifactId, ct)
            ?? throw new InvalidOperationException("Artifact not found");
        EnsureSessionOwnedByWorker(entity.SessionId, workerConnectionId, workerOwnerUserId);

        if (entity.Status != ArtifactStatus.Pending) throw new InvalidOperationException($"Artifact not pending: {entity.Status}");
        if (!await storage.ObjectExistsAsync(entity.SessionId, entity.Filename, ct))
            throw new InvalidOperationException("Object missing from storage");

        entity.Status = ArtifactStatus.Ready;
        entity.CompletedAtUtc = DateTimeOffset.UtcNow;
        entity.ContentSha256 = contentSha256;
        await db.SaveChangesAsync(ct);

        RecordAudit(workerOwnerUserId, "artifact.workerComplete", entity.Id);
        logger.LogInformation("Worker artifact {ArtifactId} upload complete.", entity.Id);
        await BroadcastArtifactChangeAsync(entity, ArtifactChangeType.Created, ct);
    }

    /// <summary>
    /// List all non-deleted artifacts for a session, newest first.
    /// </summary>
    public async Task<IReadOnlyList<ArtifactInfo>> ListAsync(string userId, string sessionId, CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        EnsureSessionOwnedByUser(sessionId, userId);
        var rows = await db.Artifacts
            .Where(a => a.SessionId == sessionId && a.Status != ArtifactStatus.Deleted)
            .OrderBy(a => a.CompletedAtUtc ?? a.CreatedAtUtc)
            .ToListAsync(ct);
        return rows.Select(MapToDto).ToList();
    }

    /// <summary>
    /// Issue a short-lived presigned GET URL for downloading the artifact content from S3.
    /// </summary>
    public async Task<DownloadUrlResponse> GetDownloadUrlAsync(string userId, string artifactId, CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var entity = await db.Artifacts.SingleOrDefaultAsync(a => a.Id == artifactId, ct)
            ?? throw new InvalidOperationException("Artifact not found");
        if (entity.OwnerUserId != userId) throw new UnauthorizedAccessException("Artifact belongs to another user");
        if (entity.Status != ArtifactStatus.Ready) throw new InvalidOperationException($"Artifact not ready: {entity.Status}");

        RecordAudit(userId, "artifact.download", entity.Id);
        return await storage.GenerateDownloadUrlAsync(entity.SessionId, entity.Filename, ct);
    }

    /// <summary>
    /// Soft-delete a single artifact: flip status to Deleted, drop the S3 object, fan out
    /// ArtifactChanged(deleted).
    /// </summary>
    public async Task DeleteAsync(string userId, string artifactId, CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var entity = await db.Artifacts.SingleOrDefaultAsync(a => a.Id == artifactId, ct)
            ?? throw new InvalidOperationException("Artifact not found");
        if (entity.OwnerUserId != userId) throw new UnauthorizedAccessException("Artifact belongs to another user");
        if (entity.Status == ArtifactStatus.Deleted) return;

        await storage.DeleteObjectAsync(entity.SessionId, entity.Filename, ct);
        entity.Status = ArtifactStatus.Deleted;
        await db.SaveChangesAsync(ct);

        RecordAudit(userId, "artifact.delete", entity.Id);
        logger.LogInformation("Artifact {ArtifactId} deleted by user.", entity.Id);
        await BroadcastArtifactChangeAsync(entity, ArtifactChangeType.Deleted, ct);
    }

    /// <summary>
    /// Worker-reported deletion of a local-mirrored file. Soft-deletes the matching row
    /// by (sessionId, filename) and fans out ArtifactChanged(deleted).
    /// </summary>
    public async Task DeleteByWorkerAsync(string sessionId, string filename, CancellationToken ct)
    {
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var entity = await db.Artifacts.SingleOrDefaultAsync(
            a => a.SessionId == sessionId && a.Filename == filename, ct);
        if (entity is null || entity.Status == ArtifactStatus.Deleted) return;

        await storage.DeleteObjectAsync(entity.SessionId, entity.Filename, ct);
        entity.Status = ArtifactStatus.Deleted;
        await db.SaveChangesAsync(ct);

        logger.LogInformation("Artifact {ArtifactId} deleted by worker (filename {Filename}).", entity.Id, filename);
        await BroadcastArtifactChangeAsync(entity, ArtifactChangeType.Deleted, ct);
    }

    /// <summary>
    /// Called by the session lifecycle when a session is terminated. Clamps every artifact's
    /// ExpiresAtUtc to now + GracePeriodHours so the user can still pull files down for a
    /// short grace window, then notifies every client to refresh the remaining-days chip.
    /// </summary>
    public async Task OnSessionTerminatedAsync(string sessionId, CancellationToken ct)
    {
        var graceEnd = DateTimeOffset.UtcNow.AddHours(_options.GracePeriodHours);
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var artifacts = await db.Artifacts
            .Where(a => a.SessionId == sessionId && a.Status != ArtifactStatus.Deleted && a.ExpiresAtUtc > graceEnd)
            .ToListAsync(ct);

        foreach (var entity in artifacts)
        {
            entity.ExpiresAtUtc = graceEnd;
        }
        await db.SaveChangesAsync(ct);

        foreach (var entity in artifacts)
        {
            await BroadcastArtifactChangeAsync(entity, ArtifactChangeType.Updated, ct);
        }
    }

    /// <summary>
    /// Periodic cleanup pass. Removes artifacts whose ExpiresAtUtc has passed: deletes the
    /// S3 object, marks the DB row Deleted, fans out ArtifactChanged(deleted).
    /// </summary>
    public async Task<int> CleanExpiredAsync(CancellationToken ct)
    {
        var now = DateTimeOffset.UtcNow;
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var expired = await db.Artifacts
            .Where(a => a.Status != ArtifactStatus.Deleted && a.ExpiresAtUtc <= now)
            .ToListAsync(ct);

        foreach (var entity in expired)
        {
            try { await storage.DeleteObjectAsync(entity.SessionId, entity.Filename, ct); }
            catch (Exception ex) { logger.LogWarning(ex, "Failed to delete S3 object for artifact {ArtifactId}.", entity.Id); }
            entity.Status = ArtifactStatus.Deleted;
            RecordAudit("system", "artifact.cleanupExpired", entity.Id);
        }
        await db.SaveChangesAsync(ct);

        foreach (var entity in expired)
        {
            await BroadcastArtifactChangeAsync(entity, ArtifactChangeType.Deleted, ct);
        }

        if (expired.Count > 0)
        {
            logger.LogInformation("Cleaned {Count} expired artifacts.", expired.Count);
        }
        return expired.Count;
    }

    private DateTimeOffset ComputeExpiresAt(DateTimeOffset now, bool sessionTerminated, ArtifactEntity? existing)
    {
        var ttlEnd = now.AddDays(_options.MaxArtifactAgeDays);
        if (sessionTerminated)
        {
            var graceEnd = now.AddHours(_options.GracePeriodHours);
            return ttlEnd < graceEnd ? ttlEnd : graceEnd;
        }
        if (existing is not null && existing.ExpiresAtUtc < ttlEnd) return existing.ExpiresAtUtc;
        return ttlEnd;
    }

    private void EnsureSessionOwnedByUser(string sessionId, string userId)
    {
        if (!sessions.TryGetSession(sessionId, out var session)) throw new InvalidOperationException("Session not found");
        if (session.UserId != userId) throw new UnauthorizedAccessException("Session belongs to another user");
    }

    private void EnsureSessionOwnedByWorker(string sessionId, string workerConnectionId, string workerOwnerUserId)
    {
        if (!sessions.TryGetSession(sessionId, out var session)) throw new InvalidOperationException("Session not found");
        if (session.WorkerConnectionId != workerConnectionId) throw new UnauthorizedAccessException("Worker connection mismatch");
        if (session.UserId != workerOwnerUserId) throw new UnauthorizedAccessException("Worker does not own session");
    }

    private async Task EnsureSessionQuotaAvailableAsync(AppDbContext db, string sessionId, CancellationToken ct)
    {
        var count = await db.Artifacts.CountAsync(a => a.SessionId == sessionId && a.Status != ArtifactStatus.Deleted, ct);
        if (count >= _options.MaxArtifactsPerSession) throw new InvalidOperationException("Session artifact quota exceeded");
    }

    private async Task BroadcastArtifactChangeAsync(ArtifactEntity entity, string changeType, CancellationToken ct)
    {
        var dto = changeType == ArtifactChangeType.Deleted ? null : MapToDto(entity);
        var evt = new ArtifactChangedEvent(entity.SessionId, entity.Id, changeType, dto);
        await terminalHub.Clients.User(entity.OwnerUserId).SendAsync("ArtifactChanged", evt, ct);
        await TerminalWebSocketConnectionRegistry.SendToUserAsync(
            entity.OwnerUserId,
            new WsArtifactChangedFrame
            {
                SessionId = entity.SessionId,
                ArtifactId = entity.Id,
                ChangeType = changeType,
                Artifact = dto
            },
            ct);
    }

    private async Task NotifyWorkerToMirrorAsync(ArtifactEntity entity, CancellationToken ct)
    {
        if (!sessions.TryGetSession(entity.SessionId, out var session) || string.IsNullOrEmpty(session.WorkerConnectionId)) return;
        var download = await storage.GenerateDownloadUrlAsync(entity.SessionId, entity.Filename, ct);
        var frame = new NotifyArtifactUploadedFrame(
            entity.SessionId,
            entity.Filename,
            download.DownloadUrl,
            entity.SizeBytes,
            entity.ContentSha256 ?? string.Empty);
        await workerCommands.NotifyArtifactUploadedAsync(session.WorkerConnectionId, frame, ct);
    }

    private static ArtifactInfo MapToDto(ArtifactEntity e) => new(
        e.Id,
        e.SessionId,
        e.Filename,
        e.SizeBytes,
        e.Status,
        e.Origin,
        e.FileCategory,
        e.CompletedAtUtc ?? e.CreatedAtUtc,
        e.ExpiresAtUtc);

    private void RecordAudit(string userId, string action, string artifactId)
    {
        auditLog.Record(new AuditLogEntry(
            Id: Guid.NewGuid().ToString("N"),
            Timestamp: DateTimeOffset.UtcNow,
            UserId: userId,
            UserName: userId,
            Action: action,
            TargetEntity: "artifact",
            TargetId: artifactId));
    }
}
