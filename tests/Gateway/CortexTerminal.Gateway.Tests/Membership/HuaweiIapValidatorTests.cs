using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CortexTerminal.Gateway.Membership;
using CortexTerminal.Gateway.Membership.Iap;
using FluentAssertions;
using Xunit;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class HuaweiIapValidatorTests
{
    [Fact]
    public async Task VerifyAsync_ValidSignedLifetime_ReturnsVerifiedDataAndUsesExpectedApi()
    {
        using var rsa = RSA.Create(2048);
        var purchaseData = JsonSerializer.Serialize(new
        {
            productId = "corterm.pro.lifetime", purchaseToken = "token-123", purchaseState = 0,
            payOrderId = "order-123", kind = 1
        });
        var signature = Convert.ToBase64String(rsa.SignData(Encoding.UTF8.GetBytes(purchaseData),
            HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1));
        var handler = new StubHandler((request, _) =>
        {
            if (request.RequestUri!.AbsoluteUri == "https://oauth.example/token")
                return Json(new { access_token = "server-token", expires_in = 3600 });
            request.RequestUri.AbsoluteUri.Should().Be("https://order.example/applications/purchases/tokens/verify");
            request.Headers.Authorization!.Scheme.Should().Be("Basic");
            Encoding.UTF8.GetString(Convert.FromBase64String(request.Headers.Authorization.Parameter!))
                .Should().Be("APPAT:server-token");
            return Json(new { responseCode = "0", purchaseTokenData = purchaseData, dataSignature = signature, signatureAlgorithm = "SHA256WithRSA" });
        });
        var options = MakeOptions(rsa);
        var validator = new HuaweiIapValidator(options, new HttpClient(handler));

        var verified = await validator.VerifyAsync("token-123", "corterm.pro.lifetime", CancellationToken.None);

        verified.PurchaseOrderId.Should().Be("order-123");
        verified.ProductKind.Should().Be(1);
        handler.Requests.Should().HaveCount(2);
    }

    [Fact]
    public async Task VerifyAsync_InvalidSignature_IsRejected()
    {
        using var rsa = RSA.Create(2048);
        var purchaseData = "{\"productId\":\"corterm.pro.lifetime\",\"purchaseToken\":\"t\",\"purchaseState\":0,\"payOrderId\":\"o\",\"kind\":1}";
        using var otherRsa = RSA.Create(2048);
        var badSignature = Convert.ToBase64String(otherRsa.SignData(Encoding.UTF8.GetBytes(purchaseData),
            HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1));
        var handler = new StubHandler((request, _) => request.RequestUri!.AbsolutePath.Contains("token")
            ? Json(new { access_token = "access", expires_in = 3600 })
            : Json(new { responseCode = "0", purchaseTokenData = purchaseData, dataSignature = badSignature }));
        var validator = new HuaweiIapValidator(MakeOptions(rsa), new HttpClient(handler));

        var act = () => validator.VerifyAsync("t", "corterm.pro.lifetime", CancellationToken.None);
        await act.Should().ThrowAsync<IapReceiptInvalidException>();
    }

    [Fact]
    public async Task VerifyAsync_UnknownProduct_IsRejectedBeforeNetwork()
    {
        using var rsa = RSA.Create(2048);
        var handler = new StubHandler((_, _) => throw new InvalidOperationException("Network should not be called"));
        var validator = new HuaweiIapValidator(MakeOptions(rsa), new HttpClient(handler));

        var act = () => validator.VerifyAsync("t", "unknown", CancellationToken.None);
        await act.Should().ThrowAsync<IapReceiptInvalidException>();
        handler.Requests.Should().BeEmpty();
    }

    [Fact]
    public async Task VerifyAsync_ExpiredSubscription_IsRejected()
    {
        using var rsa = RSA.Create(2048);
        var productData = JsonSerializer.Serialize(new
        {
            productId = "corterm.pro.month", purchaseToken = "sub-token", purchaseState = 0,
            payOrderId = "sub-order", kind = 2, expirationDate = DateTimeOffset.UtcNow.AddDays(-1).ToUnixTimeMilliseconds(),
            subIsvalid = false
        });
        var sig = Convert.ToBase64String(rsa.SignData(Encoding.UTF8.GetBytes(productData), HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1));
        var handler = new StubHandler((request, _) => request.RequestUri!.AbsolutePath.Contains("token")
            ? Json(new { access_token = "access", expires_in = 3600 })
            : Json(new { responseCode = "0", purchaseTokenData = productData, dataSignature = sig }));
        var validator = new HuaweiIapValidator(MakeOptions(rsa), new HttpClient(handler));

        var act = () => validator.VerifyAsync("sub-token", "corterm.pro.month", CancellationToken.None);
        await act.Should().ThrowAsync<IapReceiptInvalidException>();
    }

    private static IapOptions MakeOptions(RSA rsa) => new()
    {
        Huawei = new HuaweiIapOptions
        {
            ClientId = "client", ClientSecret = "secret",
            TokenUrl = "https://oauth.example/token", OrderRootUrl = "https://order.example",
            SubscriptionRootUrl = "https://subscription.example",
            PaymentPublicKey = Convert.ToBase64String(rsa.ExportSubjectPublicKeyInfo())
        }
    };

    private static HttpResponseMessage Json<T>(T body) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json")
    };

    private sealed class StubHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, CancellationToken, HttpResponseMessage> _respond;
        public List<HttpRequestMessage> Requests { get; } = [];
        public StubHandler(Func<HttpRequestMessage, CancellationToken, HttpResponseMessage> respond) => _respond = respond;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Requests.Add(request);
            return Task.FromResult(_respond(request, cancellationToken));
        }
    }
}
