using System.Net;
using System.Net.Http.Json;
using CortexTerminal.Gateway.Data;
using CortexTerminal.Gateway.Membership;
using CortexTerminal.Gateway.Membership.Iap;
using CortexTerminal.Gateway.Tests.Auth;
using FluentAssertions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class AppleWebhookTests
{
    /// <summary>
    /// Subclasses <see cref="GatewayApplicationFactory"/> (unsealed in A4) and swaps
    /// <see cref="IAppleReceiptValidator"/> for a stub that returns canned notification envelopes
    /// and transactions. The rest of the pipeline (AppleWebhookService, MembershipService,
    /// IapWebhookEvents table, User/Subscription entities) runs for real, making these end-to-end
    /// tests of the webhook state machine.
    /// </summary>
    private sealed class Factory : GatewayApplicationFactory
    {
        /// <summary>Canned notification envelope returned by the stubbed verifier.</summary>
        public AppleDecodedNotification Notification { get; set; } =
            new("TEST", "", Guid.NewGuid().ToString(), null);

        /// <summary>
        /// Canned verified transaction returned when the service re-verifies the embedded
        /// SignedTransactionInfo. Null => the stub throws IapReceiptInvalidException on verify
        /// (not used in the happy-path tests, but available for negative cases).
        /// </summary>
        public AppleVerifiedTransaction? Transaction { get; set; }

        /// <summary>When true, <see cref="IAppleReceiptValidator.VerifyNotificationAsync"/> throws.</summary>
        public bool NotificationThrows { get; set; }

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            base.ConfigureWebHost(builder);
            builder.ConfigureServices(services =>
            {
                services.RemoveAll<IAppleReceiptValidator>();
                services.AddSingleton<IAppleReceiptValidator>(new StubValidator(this));
            });
        }
    }

    private sealed class StubValidator : IAppleReceiptValidator
    {
        private readonly Factory _owner;
        public StubValidator(Factory owner) => _owner = owner;

        public Task<AppleVerifiedTransaction> VerifyAsync(string signedTransaction, CancellationToken ct)
        {
            // The webhook service calls this to re-verify the embedded SignedTransactionInfo. Hand
            // back the canned transaction so the dispatch has a real originalTransactionId / product.
            return Task.FromResult(_owner.Transaction
                ?? throw new IapReceiptInvalidException("stub: no transaction configured"));
        }

        public Task<AppleDecodedNotification> VerifyNotificationAsync(string signedPayload, CancellationToken ct)
        {
            if (_owner.NotificationThrows)
                throw new IapWebhookSignatureInvalidException("stub: bad signature");
            return Task.FromResult(_owner.Notification);
        }
    }

    private static async Task<string> SeedUserAsync(Factory factory)
    {
        var username = $"u-{Guid.NewGuid():N}".Substring(0, 16);
        await factory.SeedAsync(async db =>
        {
            db.Users.Add(new User
            {
                Id = username,
                Username = username,
                Role = "user",
                Status = "active",
                MembershipTier = MembershipTiers.Free,
                CreatedAtUtc = DateTimeOffset.UtcNow,
                UpdatedAtUtc = DateTimeOffset.UtcNow,
            });
            await db.SaveChangesAsync();
        });
        return username;
    }

    /// <summary>
    /// Grants a Pro IAP subscription for <paramref name="userId"/> so the webhook dispatch has an
    /// active subscription + Pro user to act on. Mirrors what the verify endpoint does in A4.
    /// </summary>
    private static async Task SeedProIapSubscriptionAsync(Factory factory, string userId, string originalTransactionId)
    {
        await factory.SeedAsync(async db =>
        {
            var plan = await db.Plans.SingleAsync(p => p.Code == PlanCodes.ProMonth);
            var now = DateTimeOffset.UtcNow;
            db.Subscriptions.Add(new Subscription
            {
                UserId = userId,
                PlanId = plan.Id,
                Status = SubscriptionStatuses.Active,
                Period = plan.BillingPeriod,
                StartAtUtc = now,
                ExpiresAtUtc = now.AddMonths(1),
                Source = SubscriptionSources.IapApple,
                PlatformTransactionId = originalTransactionId,
            });
            var user = await db.Users.FindAsync(userId);
            user!.MembershipTier = MembershipTiers.Pro;
            user.MembershipPlanId = plan.Id;
            user.MembershipExpiresAtUtc = now.AddMonths(1);
            user.UpdatedAtUtc = now;
            await db.SaveChangesAsync();
        });
    }

    private static HttpClient CreateAnonymousClient(Factory factory)
        => factory.CreateClient(new Microsoft.AspNetCore.Mvc.Testing.WebApplicationFactoryClientOptions
        { AllowAutoRedirect = false });

    [Fact]
    public async Task Webhook_IsAnonymous_NoAuthHeaderRequired()
    {
        // Apple calls this endpoint with no Authorization header; it must not 401.
        using var factory = new Factory();
        factory.Notification = new AppleDecodedNotification("TEST", "", Guid.NewGuid().ToString(), null);

        using var client = CreateAnonymousClient(factory);
        var resp = await client.PostAsync("/api/iap/webhook/apple",
            new StringContent("fake-signed-payload"));

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task Webhook_InvalidSignature_400()
    {
        using var factory = new Factory();
        factory.NotificationThrows = true;

        using var client = CreateAnonymousClient(factory);
        var resp = await client.PostAsync("/api/iap/webhook/apple",
            new StringContent("bad-jws"));

        resp.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var payload = await resp.Content.ReadFromJsonAsync<ErrorResponse>();
        payload.Should().NotBeNull();
        payload!.ErrorCode.Should().Be(IapWebhookSignatureInvalidException.ErrorCode);
    }

    [Fact]
    public async Task Webhook_EmptyBody_400()
    {
        using var factory = new Factory();

        using var client = CreateAnonymousClient(factory);
        var resp = await client.PostAsync("/api/iap/webhook/apple",
            new StringContent("   "));

        resp.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var payload = await resp.Content.ReadFromJsonAsync<ErrorResponse>();
        payload!.ErrorCode.Should().Be("iap_webhook_empty");
    }

    [Fact]
    public async Task Webhook_DuplicateNotification_IsIdempotent_SingleRow()
    {
        // Apple redelivers; the unique (Platform, ExternalEventId) index must dedupe to one row and
        // the second call must still 200 (so Apple stops retrying).
        using var factory = new Factory();
        var notificationUuid = Guid.NewGuid().ToString();
        factory.Notification = new AppleDecodedNotification("TEST", "", notificationUuid, null);

        using var client = CreateAnonymousClient(factory);
        var first = await client.PostAsync("/api/iap/webhook/apple", new StringContent("payload"));
        var second = await client.PostAsync("/api/iap/webhook/apple", new StringContent("payload"));

        first.StatusCode.Should().Be(HttpStatusCode.OK);
        second.StatusCode.Should().Be(HttpStatusCode.OK);

        var count = await factory.QueryAsync(async db =>
            await db.IapWebhookEvents.AsNoTracking()
                .CountAsync(e => e.Platform == "apple" && e.ExternalEventId == notificationUuid));
        count.Should().Be(1, "a redelivered notification must not create a second IapWebhookEvent row");

        // The single row should be marked processed.
        var row = await factory.QueryAsync(async db =>
            await db.IapWebhookEvents.AsNoTracking()
                .FirstAsync(e => e.Platform == "apple" && e.ExternalEventId == notificationUuid));
        row.Processed.Should().BeTrue();
    }

    [Fact]
    public async Task Webhook_DidRenew_ReGrants_AndExtendsExpiry()
    {
        using var factory = new Factory();
        var username = await SeedUserAsync(factory);
        // Original purchase already verified -> active Pro subscription tied to orig-renew-1.
        await SeedProIapSubscriptionAsync(factory, username, "orig-renew-1");

        // New expiry one year out.
        var newExpiry = new DateTimeOffset(2028, 1, 1, 0, 0, 0, TimeSpan.Zero);
        factory.Transaction = new AppleVerifiedTransaction(
            "orig-renew-1", AppleProductIds.ProYear, newExpiry.ToUnixTimeMilliseconds(), "Auto-Renewable Subscription");
        factory.Notification = new AppleDecodedNotification(
            "DID_RENEW", "", Guid.NewGuid().ToString(), "embedded-signed-tx");

        using var client = CreateAnonymousClient(factory);
        var resp = await client.PostAsync("/api/iap/webhook/apple", new StringContent("payload"));
        resp.StatusCode.Should().Be(HttpStatusCode.OK);

        var (tier, expiry) = await factory.QueryAsync(async db =>
        {
            var user = await db.Users.AsNoTracking().SingleAsync(u => u.Username == username);
            return (user.MembershipTier, user.MembershipExpiresAtUtc);
        });
        tier.Should().Be(MembershipTiers.Pro);
        expiry.Should().NotBeNull();
        expiry!.Value.ToUnixTimeMilliseconds().Should().Be(newExpiry.ToUnixTimeMilliseconds(),
            "DID_RENEW must extend the subscription expiry to the renewed transaction's expiry");
    }

    [Fact]
    public async Task Webhook_Expired_DowngradesUserToFree_AndMarksSubscriptionExpired()
    {
        using var factory = new Factory();
        var username = await SeedUserAsync(factory);
        await SeedProIapSubscriptionAsync(factory, username, "orig-exp-1");

        factory.Transaction = new AppleVerifiedTransaction(
            "orig-exp-1", AppleProductIds.ProMonth, null, "Auto-Renewable Subscription");
        factory.Notification = new AppleDecodedNotification(
            "EXPIRED", "", Guid.NewGuid().ToString(), "embedded-signed-tx");

        using var client = CreateAnonymousClient(factory);
        var resp = await client.PostAsync("/api/iap/webhook/apple", new StringContent("payload"));
        resp.StatusCode.Should().Be(HttpStatusCode.OK);

        var (tier, subStatus) = await factory.QueryAsync(async db =>
        {
            var user = await db.Users.AsNoTracking().SingleAsync(u => u.Username == username);
            var sub = await db.Subscriptions.AsNoTracking()
                .FirstAsync(s => s.UserId == user.Id && s.PlatformTransactionId == "orig-exp-1");
            return (user.MembershipTier, sub.Status);
        });
        tier.Should().Be(MembershipTiers.Free, "EXPIRED must downgrade the user to Free immediately");
        subStatus.Should().Be(SubscriptionStatuses.Expired);
    }

    [Fact]
    public async Task Webhook_Refund_DowngradesUserToFree_AndMarksSubscriptionRevoked()
    {
        using var factory = new Factory();
        var username = await SeedUserAsync(factory);
        await SeedProIapSubscriptionAsync(factory, username, "orig-refund-1");

        factory.Transaction = new AppleVerifiedTransaction(
            "orig-refund-1", AppleProductIds.ProMonth, null, "Auto-Renewable Subscription");
        factory.Notification = new AppleDecodedNotification(
            "REFUND", "", Guid.NewGuid().ToString(), "embedded-signed-tx");

        using var client = CreateAnonymousClient(factory);
        var resp = await client.PostAsync("/api/iap/webhook/apple", new StringContent("payload"));
        resp.StatusCode.Should().Be(HttpStatusCode.OK);

        var (tier, subStatus) = await factory.QueryAsync(async db =>
        {
            var user = await db.Users.AsNoTracking().SingleAsync(u => u.Username == username);
            var sub = await db.Subscriptions.AsNoTracking()
                .FirstAsync(s => s.UserId == user.Id && s.PlatformTransactionId == "orig-refund-1");
            return (user.MembershipTier, sub.Status);
        });
        tier.Should().Be(MembershipTiers.Free, "REFUND must downgrade the user to Free");
        subStatus.Should().Be(SubscriptionStatuses.Revoked);
    }

    [Fact]
    public async Task Webhook_Revoke_DowngradesUserToFree()
    {
        using var factory = new Factory();
        var username = await SeedUserAsync(factory);
        await SeedProIapSubscriptionAsync(factory, username, "orig-revoke-1");

        factory.Transaction = new AppleVerifiedTransaction(
            "orig-revoke-1", AppleProductIds.ProMonth, null, "Auto-Renewable Subscription");
        factory.Notification = new AppleDecodedNotification(
            "REVOKE", "", Guid.NewGuid().ToString(), "embedded-signed-tx");

        using var client = CreateAnonymousClient(factory);
        var resp = await client.PostAsync("/api/iap/webhook/apple", new StringContent("payload"));
        resp.StatusCode.Should().Be(HttpStatusCode.OK);

        var tier = await factory.QueryAsync(async db =>
        {
            var user = await db.Users.AsNoTracking().SingleAsync(u => u.Username == username);
            return user.MembershipTier;
        });
        tier.Should().Be(MembershipTiers.Free);
    }

    [Fact]
    public async Task Webhook_RecordOnlyType_MakesNoStateChange()
    {
        // PRICE_CHANGE (and similar) must be recorded without touching the user/subscription.
        using var factory = new Factory();
        var username = await SeedUserAsync(factory);
        await SeedProIapSubscriptionAsync(factory, username, "orig-price-1");

        factory.Notification = new AppleDecodedNotification(
            "PRICE_CHANGE", "", Guid.NewGuid().ToString(), null);

        using var client = CreateAnonymousClient(factory);
        var resp = await client.PostAsync("/api/iap/webhook/apple", new StringContent("payload"));
        resp.StatusCode.Should().Be(HttpStatusCode.OK);

        var tier = await factory.QueryAsync(async db =>
        {
            var user = await db.Users.AsNoTracking().SingleAsync(u => u.Username == username);
            return user.MembershipTier;
        });
        tier.Should().Be(MembershipTiers.Pro, "record-only types must not downgrade the user");
    }

    private sealed record ErrorResponse(string ErrorCode, string Message);
}
