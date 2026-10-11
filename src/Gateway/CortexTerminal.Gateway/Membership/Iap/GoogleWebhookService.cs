using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CortexTerminal.Gateway.Data;
using Microsoft.EntityFrameworkCore;

namespace CortexTerminal.Gateway.Membership.Iap;

/// OIDC authentication is enforced by the endpoint. RTDN is a signal to fetch
/// current Google state, never an entitlement supplied by the notification body.
public sealed class GoogleWebhookService(
    IDbContextFactory<AppDbContext> dbFactory, GooglePlayValidator validator,
    MembershipService membership, IapOptions options)
{
    public async Task HandleAsync(JsonElement body, CancellationToken ct)
    {
        if (!body.TryGetProperty("message", out var message)
            || !message.TryGetProperty("data", out var encoded)) throw new JsonException();
        var raw = Convert.FromBase64String(encoded.GetString() ?? "");
        using var payload = JsonDocument.Parse(raw);
        var data = payload.RootElement;
        if (!data.TryGetProperty("packageName", out var package)
            || package.GetString() != options.Google.PackageName) throw new JsonException();
        if (data.TryGetProperty("testNotification", out _)) return;
        JsonElement notification;
        string? productId;
        if (data.TryGetProperty("subscriptionNotification", out notification))
            productId = notification.GetProperty("subscriptionId").GetString();
        else if (data.TryGetProperty("oneTimeProductNotification", out notification))
            productId = notification.GetProperty("sku").GetString();
        else if (data.TryGetProperty("voidedPurchaseNotification", out notification))
            productId = null; // Resolve the SKU from our previously verified subscription.
        else return;
        var token = notification.GetProperty("purchaseToken").GetString();
        if (string.IsNullOrWhiteSpace(token)) throw new JsonException();
        var tokenKey = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token))).ToLowerInvariant();
        await using var db = await dbFactory.CreateDbContextAsync(ct);
        var owner = await (from sub in db.Subscriptions.AsNoTracking()
            join plan in db.Plans on sub.PlanId equals plan.Id
            where sub.Source == SubscriptionSources.IapGoogle && sub.PlatformTransactionId == tokenKey
            select new { sub.UserId, plan.Code }).FirstOrDefaultAsync(ct);
        // An initial notification may arrive before the client verifies. Its verification
        // will read the same authoritative state. Never guess another account's owner.
        if (owner is null) return;
        productId ??= owner.Code switch {
            PlanCodes.ProMonth => options.Google.ProMonthProductId,
            PlanCodes.ProYear => options.Google.ProYearProductId,
            PlanCodes.ProLifetime => options.Google.ProLifetimeProductId,
            _ => null
        };
        if (productId is null || options.Google.PlanCode(productId) is not string planCode) throw new JsonException();
        var purchase = await validator.VerifyAsync(token, productId, owner.UserId, ct, allowInactive: true);
        if (purchase.Active)
        {
            await membership.GrantFromGoogleIapAsync(owner.UserId, purchase, planCode, ct);
            await validator.AcknowledgeAsync(token, purchase, ct);
        }
        else
            await membership.RevokeGoogleIapAsync(owner.UserId, tokenKey, ct);
    }
}
