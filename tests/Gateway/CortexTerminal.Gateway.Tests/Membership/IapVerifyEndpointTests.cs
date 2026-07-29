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
            if (_owner.ValidatorThrows)
            {
                throw new IapReceiptInvalidException("stub: malformed receipt");
            }
            return Task.FromResult(_owner.Stub);
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
