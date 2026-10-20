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

public sealed class IapVerifyEndpointTests
{
    /// <summary>
    /// Subclasses <see cref="GatewayApplicationFactory"/> to inherit its InMemory DB config,
    /// JWT token minting (<see cref="GatewayApplicationFactory.CreateAuthenticatedClient(string, string?)"/>),
    /// <see cref="GatewayApplicationFactory.SeedAsync"/> / <see cref="GatewayApplicationFactory.QueryAsync{T}"/>
    /// and the plan-catalog seeding done by Program.cs. The only override swaps
    /// <see cref="IAppleReceiptValidator"/> for a stub so the test never needs a real Apple JWS —
    /// the rest of the pipeline (MembershipService.GrantFromIapAsync, AppDbContext, audit) runs for real,
    /// making this an end-to-end verify -> grant -> User.Pro test.
    /// </summary>
    private sealed class Factory : GatewayApplicationFactory
    {
        public AppleVerifiedTransaction Stub { get; set; } =
            new("orig-1", AppleProductIds.ProLifetime, null, "Non-Consumable");

        public bool ValidatorThrows { get; set; }

        /// <summary>
        /// When non-null, the legacy (StoreKit 1 / MAUI) validator stub is registered and the
        /// <see cref="LegacyStub"/> is returned; used by the legacy-path endpoint test.
        /// </summary>
        public AppleVerifiedTransaction? LegacyStub { get; set; }

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            base.ConfigureWebHost(builder);
            builder.ConfigureServices(services =>
            {
                services.RemoveAll<IAppleReceiptValidator>();
                services.AddSingleton<IAppleReceiptValidator>(new StubValidator(this));

                // The legacy validator is normally a typed HttpClient; in tests we register a plain
                // singleton instance (no HTTP calls happen because the stub short-circuits them).
                services.RemoveAll<IAppleLegacyReceiptValidator>();
                if (LegacyStub is not null)
                {
                    services.AddSingleton<IAppleLegacyReceiptValidator>(new LegacyStubValidator(LegacyStub));
                }
            });
        }
    }

    private sealed class HuaweiFactory : GatewayApplicationFactory
    {
        public HuaweiVerifiedTransaction Stub { get; set; } = new(
            "huawei-token-1", "huawei-order-1", "corterm.pro.lifetime", 0, 1, null, null);
        public bool ValidatorThrows { get; set; }

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            base.ConfigureWebHost(builder);
            builder.ConfigureServices(services =>
            {
                services.RemoveAll<IHuaweiIapValidator>();
                services.AddSingleton<IHuaweiIapValidator>(new HuaweiStubValidator(this));
            });
        }
    }

    private sealed class HuaweiStubValidator : IHuaweiIapValidator
    {
        private readonly HuaweiFactory _factory;
        public HuaweiStubValidator(HuaweiFactory factory) => _factory = factory;
        public Task<HuaweiVerifiedTransaction> VerifyAsync(string purchaseToken, string purchaseOrderId, string productId, CancellationToken ct)
        {
            if (_factory.ValidatorThrows) throw new IapReceiptInvalidException("stub: invalid Huawei token");
            return Task.FromResult(_factory.Stub);
        }

        public Task<HuaweiVerifiedTransaction> VerifyOrderAsync(string purchaseToken, string purchaseOrderId, string productId, int expectedKind, CancellationToken ct)
        {
            if (_factory.ValidatorThrows) throw new IapReceiptInvalidException("stub: invalid Huawei token");
            return Task.FromResult(_factory.Stub);
        }

        public Task<HuaweiVerifiedTransaction> VerifySubscriptionJwsAsync(string jws, string productId, CancellationToken ct)
        {
            if (_factory.ValidatorThrows) throw new IapReceiptInvalidException("stub: invalid Huawei subscription JWS");
            return Task.FromResult(_factory.Stub);
        }
    }

    private sealed class StubValidator : IAppleReceiptValidator
    {
        private readonly Factory _owner;
        public StubValidator(Factory owner) => _owner = owner;

        public Task<AppleVerifiedTransaction> VerifyAsync(string signedTransaction, CancellationToken ct)
        {
            if (_owner.ValidatorThrows)
            {
                throw new IapReceiptInvalidException("stub: malformed receipt");
            }
            return Task.FromResult(_owner.Stub);
        }

        // The verify endpoint never triggers notification verification; this stub exists only to
        // satisfy the IAppleReceiptValidator contract (webhook tests use their own stub).
        public Task<AppleDecodedNotification> VerifyNotificationAsync(string signedPayload, CancellationToken ct)
            => throw new NotImplementedException();
    }

    /// <summary>
    /// Stub for the StoreKit 1 legacy validator — exercises the A4 routing decision
    /// (<c>receiptFormat=legacy</c>) end-to-end through GrantFromIapAsync.
    /// </summary>
    private sealed class LegacyStubValidator : IAppleLegacyReceiptValidator
    {
        private readonly AppleVerifiedTransaction _tx;
        public LegacyStubValidator(AppleVerifiedTransaction tx) => _tx = tx;
        public Task<AppleVerifiedTransaction> VerifyAsync(string receiptDataBase64, CancellationToken ct)
            => Task.FromResult(_tx);
    }

    private static async Task<string> SeedUserAsync(GatewayApplicationFactory factory)
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

    [Fact]
    public async Task Verify_AppleLifetime_UpgradeToPro()
    {
        using var factory = new Factory();
        factory.Stub = new AppleVerifiedTransaction("orig-1", AppleProductIds.ProLifetime, null, "Non-Consumable");
        var username = await SeedUserAsync(factory);

        using var client = factory.CreateAuthenticatedClient(username);
        var resp = await client.PostAsJsonAsync("/api/iap/purchase/verify",
            new { platform = "apple", productId = AppleProductIds.ProLifetime, signedTransaction = "fake-jws" });

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        var payload = await resp.Content.ReadFromJsonAsync<VerifyResponse>();
        payload.Should().NotBeNull();
        payload!.IsActive.Should().BeTrue();
        payload.SubscriptionId.Should().NotBeNullOrWhiteSpace();

        var tier = await factory.QueryAsync(async db =>
        {
            var user = await db.Users.AsNoTracking().FirstAsync(u => u.Username == username);
            return user.MembershipTier;
        });
        tier.Should().Be(MembershipTiers.Pro);
    }

    [Fact]
    public async Task Verify_HuaweiLifetime_GrantsProAndIsIdempotent()
    {
        using var factory = new HuaweiFactory();
        var username = await SeedUserAsync(factory);
        using var client = factory.CreateAuthenticatedClient(username);

        async Task<HttpResponseMessage> Verify() => await client.PostAsJsonAsync("/api/iap/purchase/verify", new
        {
            platform = "huawei", productId = "corterm.pro.lifetime", purchaseToken = "huawei-token-1", purchaseOrderId = "huawei-order-1"
        });

        using var first = await Verify();
        using var duplicate = await Verify();
        first.StatusCode.Should().Be(HttpStatusCode.OK);
        duplicate.StatusCode.Should().Be(HttpStatusCode.OK);
        var state = await factory.QueryAsync(async db => new
        {
            User = await db.Users.AsNoTracking().FirstAsync(u => u.Username == username),
            Subs = await db.Subscriptions.AsNoTracking().CountAsync(s => s.PlatformTransactionId == "huawei-token-1"),
            Orders = await db.MembershipOrders.AsNoTracking().CountAsync(o => o.ProviderOrderId == "huawei-order-1")
        });
        state.User.MembershipTier.Should().Be(MembershipTiers.Pro);
        state.Subs.Should().Be(1);
        state.Orders.Should().Be(1);
    }

    [Fact]
    public async Task Verify_HuaweiRejectedToken_DoesNotGrantMembership()
    {
        using var factory = new HuaweiFactory { ValidatorThrows = true };
        var username = await SeedUserAsync(factory);
        using var client = factory.CreateAuthenticatedClient(username);
        using var response = await client.PostAsJsonAsync("/api/iap/purchase/verify", new
        {
            platform = "huawei", productId = "corterm.pro.lifetime", purchaseToken = "invalid"
        });

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var tier = await factory.QueryAsync(async db =>
            (await db.Users.AsNoTracking().FirstAsync(u => u.Username == username)).MembershipTier);
        tier.Should().Be(MembershipTiers.Free);
    }

    /// <summary>
    /// StoreKit 1 (MAUI / Plugin.InAppBilling) path: client sends <c>receiptFormat=legacy</c>
    /// with the base64 receipt blob. The endpoint must route to
    /// <see cref="IAppleLegacyReceiptValidator"/> and grant Pro exactly like the JWS path.
    /// </summary>
    [Fact]
    public async Task Verify_LegacyReceiptFormat_RoutesToLegacyValidatorAndGrantsPro()
    {
        using var factory = new Factory
        {
            LegacyStub = new AppleVerifiedTransaction("orig-legacy", AppleProductIds.ProLifetime, null, "Non-Consumable")
        };
        var username = await SeedUserAsync(factory);

        using var client = factory.CreateAuthenticatedClient(username);
        var resp = await client.PostAsJsonAsync("/api/iap/purchase/verify",
            new
            {
                platform = "apple",
                productId = AppleProductIds.ProLifetime,
                signedTransaction = "base64-receipt-data==",
                receiptFormat = "legacy"
            });

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        var payload = await resp.Content.ReadFromJsonAsync<VerifyResponse>();
        payload.Should().NotBeNull();
        payload!.IsActive.Should().BeTrue();
        payload.SubscriptionId.Should().NotBeNullOrWhiteSpace();

        var tier = await factory.QueryAsync(async db =>
        {
            var user = await db.Users.AsNoTracking().FirstAsync(u => u.Username == username);
            return user.MembershipTier;
        });
        tier.Should().Be(MembershipTiers.Pro);
    }

    [Fact]
    public async Task Verify_UnsupportedPlatform_400()
    {
        using var factory = new Factory();
        var username = await SeedUserAsync(factory);

        using var client = factory.CreateAuthenticatedClient(username);
        var resp = await client.PostAsJsonAsync("/api/iap/purchase/verify",
            new { platform = "google", productId = "x", signedTransaction = "y" });

        resp.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Verify_InvalidReceipt_400()
    {
        using var factory = new Factory();
        factory.ValidatorThrows = true;
        var username = await SeedUserAsync(factory);

        using var client = factory.CreateAuthenticatedClient(username);
        var resp = await client.PostAsJsonAsync("/api/iap/purchase/verify",
            new { platform = "apple", productId = AppleProductIds.ProLifetime, signedTransaction = "bad-jws" });

        resp.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var payload = await resp.Content.ReadFromJsonAsync<ErrorResponse>();
        payload.Should().NotBeNull();
        payload!.ErrorCode.Should().Be(IapReceiptInvalidException.ErrorCode);
    }

    [Fact]
    public async Task Verify_UnknownProduct_400()
    {
        using var factory = new Factory();
        factory.Stub = new AppleVerifiedTransaction("orig-2", "corterm.unknown", null, "Non-Consumable");
        var username = await SeedUserAsync(factory);

        using var client = factory.CreateAuthenticatedClient(username);
        var resp = await client.PostAsJsonAsync("/api/iap/purchase/verify",
            new { platform = "apple", productId = "corterm.unknown", signedTransaction = "fake-jws" });

        resp.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        var payload = await resp.Content.ReadFromJsonAsync<ErrorResponse>();
        payload.Should().NotBeNull();
        payload!.ErrorCode.Should().Be("iap_invalid_product");
    }

    [Fact]
    public async Task Verify_RequiresAuthentication()
    {
        using var factory = new Factory();
        using var client = factory.CreateClient();
        var resp = await client.PostAsJsonAsync("/api/iap/purchase/verify",
            new { platform = "apple", productId = AppleProductIds.ProLifetime, signedTransaction = "fake-jws" });
        resp.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    private sealed record VerifyResponse(string SubscriptionId, bool IsActive, DateTimeOffset? ExpiresAtUtc);
    private sealed record ErrorResponse(string ErrorCode, string Message);
}
