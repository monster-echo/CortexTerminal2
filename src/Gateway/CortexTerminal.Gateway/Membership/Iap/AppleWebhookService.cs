using CortexTerminal.Gateway.Data;
using Microsoft.EntityFrameworkCore;

namespace CortexTerminal.Gateway.Membership.Iap;

/// <summary>
/// Handles an inbound App Store Server Notification V2. Responsibilities, in order:
///
/// <list type="number">
/// <item><description>
/// Verify the JWS <c>signedPayload</c> via <see cref="IAppleReceiptValidator.VerifyNotificationAsync"/>
/// (signature + Apple root CA chain + bundle id + environment). A verification failure is
/// rethrown as <see cref="IapWebhookSignatureInvalidException"/> — the endpoint maps it to 400,
/// it is never swallowed.
/// </description></item>
/// <item><description>
/// Idempotency: insert a row into <c>IapWebhookEvents</c> keyed by
/// <c>(Platform=apple, ExternalEventId=NotificationUuid)</c>. Apple redelivers notifications on
/// retry, so the unique index is the dedup gate — a duplicate insert throws <c>DbUpdateException</c>
/// and the handler returns a no-op success.
/// </description></item>
/// <item><description>
/// Dispatch by <c>NotificationType</c>:
/// <c>DID_RENEW</c>/<c>SUBSCRIPTION_RENEWED</c> re-verifies the embedded transaction and re-grants
/// (extends expiry); <c>EXPIRED</c>/<c>GRACE_PERIOD_EXPIRED</c> downgrades the user to Free and
/// marks the subscription Expired; <c>REFUND</c>/<c>REVOKE</c> downgrades to Free and marks the
/// subscription Revoked; anything else is recorded only (no state change). The user is resolved
/// from the existing IAP subscription matching <c>OriginalTransactionId</c>.
/// </description></item>
/// <item><description>
/// On successful dispatch the <c>IapWebhookEvent.Processed</c> flag is set; a dispatch failure
/// leaves it <c>false</c> so a future replay can retry.
/// </description></item>
/// </list>
/// </summary>
public sealed class AppleWebhookService
{
    private const string Platform = "apple";

    private readonly IAppleReceiptValidator _validator;
    private readonly MembershipService _membership;
    private readonly IDbContextFactory<AppDbContext> _dbFactory;
    private readonly ILogger<AppleWebhookService> _logger;

    public AppleWebhookService(
        IAppleReceiptValidator validator,
        MembershipService membership,
        IDbContextFactory<AppDbContext> dbFactory,
        ILogger<AppleWebhookService> logger)
    {
        _validator = validator;
        _membership = membership;
        _dbFactory = dbFactory;
        _logger = logger;
    }

    /// <summary>
    /// Returns <c>true</c> when a dispatch actually happened (new event), <c>false</c> when the
    /// notification was a duplicate of an already-processed event. The endpoint returns 200 either
    /// way so Apple stops retrying.
    /// </summary>
    public async Task<bool> HandleAsync(string signedPayload, CancellationToken ct)
    {
        // 1. Verify JWS signature/chain. Throws IapWebhookSignatureInvalidException on failure —
        //    the endpoint maps that to 400. We deliberately do NOT catch it here.
        var notification = await _validator.VerifyNotificationAsync(signedPayload, ct);

        var externalEventId = notification.NotificationUuid;
        if (string.IsNullOrEmpty(externalEventId))
        {
            // Apple always sends a NotificationUuid; an absent one means a malformed/unsupported
            // payload we cannot dedup — fail loudly rather than risk duplicate processing.
            throw new IapWebhookSignatureInvalidException(
                "Apple notification is missing NotificationUuid; cannot deduplicate.");
        }

        // 2. Idempotency. We check-then-insert: a pre-existing event means Apple redelivered an
        // already-processed notification, so we return a no-op success. The production unique index
        // on (Platform, ExternalEventId) is the concurrency backstop for the rare race; the explicit
        // query also covers the EF InMemory provider (used in tests), which does not enforce indexes.
        await using (var insertDb = await _dbFactory.CreateDbContextAsync(ct))
        {
            var alreadySeen = await insertDb.IapWebhookEvents.AnyAsync(
                e => e.Platform == Platform && e.ExternalEventId == externalEventId, ct);
            if (alreadySeen)
            {
                _logger.LogInformation(
                    "Apple webhook event {ExternalEventId} already processed; ignoring duplicate.",
                    externalEventId);
                return false;
            }

            insertDb.IapWebhookEvents.Add(new IapWebhookEvent
            {
                Platform = Platform,
                ExternalEventId = externalEventId,
                RawPayload = signedPayload,
                ReceivedAtUtc = DateTimeOffset.UtcNow,
                Processed = false,
            });
            try
            {
                await insertDb.SaveChangesAsync(ct);
            }
            catch (DbUpdateException ex)
            {
                // Unique-constraint hit under the rare check-then-insert race (two concurrent
                // deliveries of the same NotificationUuid). Treat as a duplicate.
                _logger.LogInformation(ex,
                    "Apple webhook event {ExternalEventId} already processed; ignoring duplicate.",
                    externalEventId);
                return false;
            }
        }

        // 3. Dispatch by notification type. A dispatch exception leaves Processed=false so a
        //    replay can retry; we let it propagate so the endpoint logs/returns it.
        await DispatchAsync(notification, ct);

        // 4. Mark processed on success.
        await using var markDb = await _dbFactory.CreateDbContextAsync(ct);
        var row = await markDb.IapWebhookEvents.FirstAsync(
            e => e.Platform == Platform && e.ExternalEventId == externalEventId, ct);
        row.Processed = true;
        await markDb.SaveChangesAsync(ct);
        return true;
    }

    private async Task DispatchAsync(AppleDecodedNotification notification, CancellationToken ct)
    {
        // Notification types are documented uppercase by Apple (DID_RENEW, EXPIRED, ...). Normalize
        // to uppercase so a sandbox sending lowercase is still handled.
        var type = (notification.NotificationType ?? "").ToUpperInvariant();

        switch (type)
        {
            case AppleNotificationTypes.DidRenew:
            case AppleNotificationTypes.SubscriptionRenewed:
                await HandleRenewalAsync(notification, ct);
                return;

            case AppleNotificationTypes.Expired:
            case AppleNotificationTypes.GracePeriodExpired:
                await DowngradeAsync(notification, SubscriptionStatuses.Expired, ct);
                return;

            case AppleNotificationTypes.Refund:
            case AppleNotificationTypes.Revoke:
                await DowngradeAsync(notification, SubscriptionStatuses.Revoked, ct);
                return;

            default:
                // PRICE_CHANGE, DID_CHANGE_RENEWAL_STATUS, TEST, etc. — record only (the
                // IapWebhookEvent row already captures the raw payload for auditing).
                _logger.LogInformation(
                    "Apple webhook {NotificationType} recorded without state change.", type);
                return;
        }
    }

    /// <summary>
    /// DID_RENEW / SUBSCRIPTION_RENEWED: the embedded <c>SignedTransactionInfo</c> carries the
    /// renewed expiry. Verify it and extend the existing active subscription's expiry in place via
    /// <see cref="MembershipService.ExtendFromIapRenewalAsync"/>. A renewal is NOT a new grant —
    /// <see cref="MembershipService.GrantFromIapAsync"/> would short-circuit on the existing active
    /// subscription and leave the stale expiry, so we use the purpose-built extend method instead.
    /// If Apple did not embed a transaction, or no active subscription exists, we record-only.
    /// </summary>
    private async Task HandleRenewalAsync(AppleDecodedNotification notification, CancellationToken ct)
    {
        if (string.IsNullOrEmpty(notification.SignedTransactionInfo))
        {
            _logger.LogWarning(
                "Apple webhook {NotificationType} carried no SignedTransactionInfo; recording only.",
                notification.NotificationType);
            return;
        }

        // Verify the embedded transaction JWS with the same verifier, then resolve the owning user
        // from the existing IAP subscription (the webhook has no user id, only Apple's transaction).
        var verified = await _validator.VerifyAsync(notification.SignedTransactionInfo, ct);
        var userId = await ResolveUserIdByOriginalTransactionIdAsync(verified.OriginalTransactionId, ct);
        if (userId is null)
        {
            // No prior purchase for this originalTransactionId — nothing to renew. This can happen
            // if the initial verify hasn't run yet; record-only is the safe choice.
            _logger.LogWarning(
                "Apple renewal {OriginalTransactionId} has no matching subscription; recording only.",
                verified.OriginalTransactionId);
            return;
        }

        await _membership.ExtendFromIapRenewalAsync(userId, verified, ct);
    }

    /// <summary>
    /// EXPIRED / GRACE_PERIOD_EXPIRED / REFUND / REVOKE: downgrade the owning user to Free and
    /// mark the matching IAP subscription with <paramref name="targetStatus"/>. If no matching
    /// subscription exists (e.g. the user never verified), there is nothing to downgrade —
    /// record-only. EntitlementService will pick up the tier change on the next read.
    /// </summary>
    private async Task DowngradeAsync(
        AppleDecodedNotification notification, string targetStatus, CancellationToken ct)
    {
        // We need the originalTransactionId to locate the subscription. For REFUND/REVOKE/EXPIRED
        // Apple embeds SignedTransactionInfo; if absent we cannot target a subscription precisely,
        // so record-only (do not guess by user — that would risk downgrading the wrong account).
        if (string.IsNullOrEmpty(notification.SignedTransactionInfo))
        {
            _logger.LogWarning(
                "Apple webhook {NotificationType} carried no SignedTransactionInfo; recording only.",
                notification.NotificationType);
            return;
        }

        var verified = await _validator.VerifyAsync(notification.SignedTransactionInfo, ct);
        await using var db = await _dbFactory.CreateDbContextAsync(ct);
        var sub = await db.Subscriptions.FirstOrDefaultAsync(
            s => s.Source == SubscriptionSources.IapApple
                 && s.PlatformTransactionId == verified.OriginalTransactionId
                 && s.Status == SubscriptionStatuses.Active, ct);
        if (sub is null)
        {
            _logger.LogInformation(
                "Apple downgrade {NotificationType} for {OriginalTransactionId} has no active subscription; recording only.",
                notification.NotificationType, verified.OriginalTransactionId);
            return;
        }

        var now = DateTimeOffset.UtcNow;
        sub.Status = targetStatus;
        sub.UpdatedAtUtc = now;

        var user = await db.Users.FindAsync(new object?[] { sub.UserId }, ct);
        if (user is not null)
        {
            user.MembershipTier = MembershipTiers.Free;
            user.MembershipPlanId = null;
            user.MembershipExpiresAtUtc = null;
            user.UpdatedAtUtc = now;
        }

        await db.SaveChangesAsync(ct);
    }

    private async Task<string?> ResolveUserIdByOriginalTransactionIdAsync(
        string originalTransactionId, CancellationToken ct)
    {
        await using var db = await _dbFactory.CreateDbContextAsync(ct);
        var sub = await db.Subscriptions.AsNoTracking().FirstOrDefaultAsync(
            s => s.Source == SubscriptionSources.IapApple
                 && s.PlatformTransactionId == originalTransactionId, ct);
        return sub?.UserId;
    }
}

/// <summary>
/// Apple App Store Server Notification V2 type strings (uppercase, as documented). Only the ones
/// we dispatch on are listed; everything else falls through to record-only.
/// </summary>
internal static class AppleNotificationTypes
{
    public const string DidRenew = "DID_RENEW";
    public const string SubscriptionRenewed = "SUBSCRIPTION_RENEWED";
    public const string Expired = "EXPIRED";
    public const string GracePeriodExpired = "GRACE_PERIOD_EXPIRED";
    public const string Refund = "REFUND";
    public const string Revoke = "REVOKE";
}
