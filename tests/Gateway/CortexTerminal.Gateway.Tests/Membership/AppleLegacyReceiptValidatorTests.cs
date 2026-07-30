using System.Net;
using System.Text;
using CortexTerminal.Gateway.Membership;
using CortexTerminal.Gateway.Membership.Iap;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class AppleLegacyReceiptValidatorTests
{
    private const string ProductionUrl = "https://buy.itunes.apple.com/verifyReceipt";
    private const string SandboxUrl = "https://sandbox.itunes.apple.com/verifyReceipt";

    private static IapOptions Options(string secret = "secret") =>
        new() { Apple = { SharedSecret = secret } };

    /// <summary>
    /// A stub HttpHandler that returns a canned response per requested URL, capturing the body so
    /// the test can assert what we POSTed to Apple.
    /// </summary>
    private sealed class StubHandler : HttpMessageHandler
    {
        private readonly Dictionary<string, string> _responsesByUrl;
        public List<(string Url, string Body)> Calls { get; } = new();

        public StubHandler(Dictionary<string, string> responsesByUrl) => _responsesByUrl = responsesByUrl;

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var url = request.RequestUri?.AbsoluteUri ?? "";
            var body = request.Content is null
                ? ""
                : request.Content.ReadAsStringAsync(cancellationToken).GetAwaiter().GetResult();
            Calls.Add((url, body));

            if (!_responsesByUrl.TryGetValue(url, out var json))
            {
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound) { Content = new StringContent("") });
            }
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            });
        }
    }

    private static AppleLegacyReceiptValidator CreateValidator(StubHandler handler, string secret = "secret")
        => new(Options(secret), new HttpClient(handler), NullLogger<AppleLegacyReceiptValidator>.Instance);

    [Fact]
    public async Task VerifyAsync_AutoRenewableSubscription_MapsLatestEntry()
    {
        // latest_receipt_info holds every renewal period; the LAST entry is the active one.
        string json = """
        {
            "status": 0,
            "receipt": { "in_app": [ { "original_transaction_id": "old", "product_id": "p1", "expires_date_ms": "1" } ] },
            "latest_receipt_info": [
                { "original_transaction_id": "orig-1", "product_id": "corterm.pro.month", "expires_date_ms": 1700000000000 },
                { "original_transaction_id": "orig-1", "product_id": "corterm.pro.month", "expires_date_ms": 1700000060000 }
            ]
        }
        """;
        var handler = new StubHandler(new() { [ProductionUrl] = json });
        var sut = CreateValidator(handler);

        var tx = await sut.VerifyAsync("receipt-b64", CancellationToken.None);

        tx.Should().BeEquivalentTo(new AppleVerifiedTransaction(
            OriginalTransactionId: "orig-1",
            ProductId: "corterm.pro.month",
            ExpiresDateMs: 1700000060000L,
            Type: "Auto-Renewable Subscription"
        ));
        handler.Calls.Should().ContainSingle().Which.Url.Should().Be(ProductionUrl);
    }

    [Fact]
    public async Task VerifyAsync_NonConsumable_MapsNullExpiryAndFallsBackToInApp()
    {
        // Non-renewing purchases: latest_receipt_info is absent; fall back to receipt.in_app and
        // surface ExpiresDateMs = null.
        string json = """
        {
            "status": 0,
            "receipt": {
                "in_app": [
                    { "original_transaction_id": "orig-2", "product_id": "corterm.pro.lifetime", "expires_date_ms": "0" }
                ]
            }
        }
        """;
        var handler = new StubHandler(new() { [ProductionUrl] = json });
        var sut = CreateValidator(handler);

        var tx = await sut.VerifyAsync("b64", CancellationToken.None);

        tx.OriginalTransactionId.Should().Be("orig-2");
        tx.ProductId.Should().Be("corterm.pro.lifetime");
        tx.ExpiresDateMs.Should().BeNull();
        tx.Type.Should().Be("Non-Consumable");
    }

    [Fact]
    public async Task VerifyAsync_NonConsumable_WithAbsentExpiresDate_MapsNull()
    {
        // Some non-consumable payloads omit expires_date_ms entirely.
        string json = """
        {
            "status": 0,
            "receipt": { "in_app": [ { "original_transaction_id": "o", "product_id": "p" } ] }
        }
        """;
        var handler = new StubHandler(new() { [ProductionUrl] = json });
        var sut = CreateValidator(handler);

        var tx = await sut.VerifyAsync("b64", CancellationToken.None);

        tx.ExpiresDateMs.Should().BeNull();
        tx.Type.Should().Be("Non-Consumable");
    }

    [Fact]
    public async Task VerifyAsync_Status21007_RetriesSandboxEndpoint()
    {
        // Standard Apple flow: production first, 21007 -> retry sandbox.
        string prodJson = """
        { "status": 21007, "receipt": {} }
        """;
        string sandboxJson = """
        {
            "status": 0,
            "latest_receipt_info": [
                { "original_transaction_id": "sb-1", "product_id": "corterm.pro.month", "expires_date_ms": 1700000000000 }
            ]
        }
        """;
        var handler = new StubHandler(new()
        {
            [ProductionUrl] = prodJson,
            [SandboxUrl] = sandboxJson
        });
        var sut = CreateValidator(handler);

        var tx = await sut.VerifyAsync("b64", CancellationToken.None);

        tx.OriginalTransactionId.Should().Be("sb-1");
        handler.Calls.Select(c => c.Url).Should().Equal(ProductionUrl, SandboxUrl);
    }

    [Fact]
    public async Task VerifyAsync_NonZeroStatus_ThrowsInvalidReceipt()
    {
        // Any status != 0 (and != 21007 which triggers the sandbox retry) is a hard failure.
        string json = """
        { "status": 21002, "receipt": {} }
        """;
        var handler = new StubHandler(new() { [ProductionUrl] = json });
        var sut = CreateValidator(handler);

        var act = () => sut.VerifyAsync("b64", CancellationToken.None);

        await act.Should().ThrowAsync<IapReceiptInvalidException>()
            .WithMessage("*status 21002*");
    }

    [Fact]
    public async Task VerifyAsync_Status21007InSandbox_StillRejected()
    {
        // If sandbox itself returns 21007, it's a genuine failure (no further retry available).
        string json = """
        { "status": 21007, "receipt": {} }
        """;
        var handler = new StubHandler(new()
        {
            [ProductionUrl] = json,
            [SandboxUrl] = json
        });
        var sut = CreateValidator(handler);

        var act = () => sut.VerifyAsync("b64", CancellationToken.None);

        await act.Should().ThrowAsync<IapReceiptInvalidException>();
    }

    [Fact]
    public async Task VerifyAsync_NoTransactionEntries_ThrowsInvalidReceipt()
    {
        // status 0 but the receipt body is empty -> we cannot grant anything.
        string json = """
        { "status": 0, "receipt": { "in_app": [] } }
        """;
        var handler = new StubHandler(new() { [ProductionUrl] = json });
        var sut = CreateValidator(handler);

        var act = () => sut.VerifyAsync("b64", CancellationToken.None);

        await act.Should().ThrowAsync<IapReceiptInvalidException>()
            .WithMessage("*no in-app purchase*");
    }

    [Fact]
    public async Task VerifyAsync_PostsSharedSecretAndPassword()
    {
        string json = """
        {
            "status": 0,
            "receipt": { "in_app": [ { "original_transaction_id": "o", "product_id": "p", "expires_date_ms": 0 } ] }
        }
        """;
        var handler = new StubHandler(new() { [ProductionUrl] = json });
        var sut = CreateValidator(handler, secret: "my-shared-secret");

        await sut.VerifyAsync("receipt-data==", CancellationToken.None);

        var body = handler.Calls.Single().Body;
        body.Should().Contain("\"receipt-data\":\"receipt-data==\"");
        body.Should().Contain("\"password\":\"my-shared-secret\"");
        body.Should().Contain("\"exclude-old-transactions\":true");
    }
}
