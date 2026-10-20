using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using CortexTerminal.Gateway.Membership;
using CortexTerminal.Gateway.Membership.Iap;
using FluentAssertions;
using Xunit;
using Microsoft.Extensions.Logging.Abstractions;

namespace CortexTerminal.Gateway.Tests.Membership;

public sealed class HuaweiIapValidatorTests
{
    private const string RootUrl = "https://iap.example";
    private const string AppId = "app-1";

    [Fact]
    public async Task VerifyAsync_Lifetime_QueriesOrderStatusWithJwtAndMapsFields()
    {
        // 华为订单状态查询的响应是 JWS 包装的订单数据（jwsPurchaseOrder）
        using var orderKey = ECDsa.Create();
        var orderPayload = JsonSerializer.Serialize(new Dictionary<string, object>
        {
            ["purchaseOrderId"] = "order-123",
            ["purchaseToken"] = "token-123",
            ["applicationId"] = AppId,
            ["productId"] = "corterm.pro.lifetime",
            ["productType"] = "1",
            ["environment"] = "SANDBOX",
            ["price"] = 26800,
            ["currency"] = "CNY"
        });
        var orderJws = SignJws(orderKey, orderPayload);

        string? capturedJwt = null;
        string? capturedBody = null;
        var handler = new StubHandler((request, body) =>
        {
            request.RequestUri!.AbsoluteUri.Should().Be($"{RootUrl}/order/harmony/v1/application/order/status/query");
            request.Headers.Authorization!.Scheme.Should().Be("Bearer");
            capturedJwt = request.Headers.Authorization.Parameter;
            capturedBody = body;
            return Json(new { responseCode = "0", responseMessage = "success", jwsPurchaseOrder = orderJws });
        });
        using var key = ECDsa.Create();
        var validator = new HuaweiIapValidator(MakeOptions(key), new HttpClient(handler),
            NullLogger<HuaweiIapValidator>.Instance);

        var verified = await validator.VerifyAsync("token-123", "order-123", "corterm.pro.lifetime", CancellationToken.None);

        verified.PurchaseToken.Should().Be("token-123");
        verified.PurchaseOrderId.Should().Be("order-123");
        verified.ProductKind.Should().Be(1);
        handler.Requests.Should().HaveCount(1);

        // JWT：三段式，header 校验 kid/alg，payload 校验 iss/aud/aid/digest
        var parts = capturedJwt!.Split('.');
        parts.Should().HaveCount(3);
        using var headerDoc = DecodeJson(parts[0]);
        var header = headerDoc.RootElement;
        header.GetProperty("alg").GetString().Should().Be("ES256");
        header.GetProperty("typ").GetString().Should().Be("JWT");
        header.GetProperty("kid").GetString().Should().Be("kid-1");
        using var payloadDoc = DecodeJson(parts[1]);
        var payload = payloadDoc.RootElement;
        payload.GetProperty("iss").GetString().Should().Be("issuer-1");
        payload.GetProperty("aud").GetString().Should().Be("iap-v1");
        payload.GetProperty("aid").GetString().Should().Be(AppId);
        // digest 必须是请求体 JSON 的 SHA-256（小写十六进制）
        var digest = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(capturedBody!))).ToLowerInvariant();
        payload.GetProperty("digest").GetString().Should().Be(digest);
    }

    [Fact]
    public async Task VerifyAsync_MismatchedProduct_IsRejected()
    {
        // 华为返回的订单是 JWS 包装的，且 productId 与请求不符
        using var orderKey = ECDsa.Create();
        var orderPayload = JsonSerializer.Serialize(new Dictionary<string, object>
        {
            ["purchaseOrderId"] = "order-123",
            ["purchaseToken"] = "token-123",
            ["applicationId"] = AppId,
            ["productId"] = "corterm.pro.lifetime",
            ["productType"] = "1"
        });
        var orderJws = SignJws(orderKey, orderPayload);
        var handler = new StubHandler((_, _) => Json(new { responseCode = "0", jwsPurchaseOrder = orderJws }));
        using var key = ECDsa.Create();
        var validator = new HuaweiIapValidator(MakeOptions(key), new HttpClient(handler),
            NullLogger<HuaweiIapValidator>.Instance);

        var act = () => validator.VerifyAsync("token-123", "order-123", "corterm.pro.month", CancellationToken.None);
        await act.Should().ThrowAsync<IapReceiptInvalidException>();
        handler.Requests.Should().HaveCount(1);
    }

    [Fact]
    public async Task VerifyAsync_UnknownProduct_IsRejectedBeforeNetwork()
    {
        var handler = new StubHandler((_, _) => throw new InvalidOperationException("Network should not be called"));
        using var key = ECDsa.Create();
        var validator = new HuaweiIapValidator(MakeOptions(key), new HttpClient(handler),
            NullLogger<HuaweiIapValidator>.Instance);

        var act = () => validator.VerifyAsync("t", "o", "unknown", CancellationToken.None);
        await act.Should().ThrowAsync<IapReceiptInvalidException>();
        handler.Requests.Should().BeEmpty();
    }

    [Fact]
    public async Task VerifyAsync_MissingServerKeyConfig_Throws()
    {
        var handler = new StubHandler((_, _) => throw new InvalidOperationException("Network should not be called"));
        var options = MakeOptions(ECDsa.Create());
        options.Huawei.IssuerId = "";
        var validator = new HuaweiIapValidator(options, new HttpClient(handler), NullLogger<HuaweiIapValidator>.Instance);

        var act = () => validator.VerifyAsync("t", "o", "corterm.pro.lifetime", CancellationToken.None);
        await act.Should().ThrowAsync<IapReceiptInvalidException>();
        handler.Requests.Should().BeEmpty();
    }

    [Fact]
    public async Task VerifySubscriptionJwsAsync_ValidJws_QueriesStatusAndGrants()
    {
        using var signingKey = ECDsa.Create();
        var (jws, _) = BuildSubscriptionJws(signingKey, "sub-token", "order-9");

        string? capturedBody = null;
        var handler = new StubHandler((request, body) =>
        {
            request.RequestUri!.AbsoluteUri.Should().Be(
                $"{RootUrl}/subscription/harmony/v1/application/subscription/status/query");
            request.Headers.Authorization!.Scheme.Should().Be("Bearer");
            capturedBody = body;
            return Json(new
            {
                responseCode = "0",
                environment = "SANDBOX",
                applicationId = AppId,
                packageName = "top.rwecho.cortexterminal",
                subGroupId = "group-1",
                lastSubscriptionStatus = new
                {
                    subGroupGenerationId = "gen-1",
                    subscriptionId = "sub-1",
                    purchaseToken = "sub-token",
                    status = "1",
                    expiresTime = DateTimeOffset.UtcNow.AddDays(30).ToUnixTimeMilliseconds(),
                    lastPurchaseOrder = new { orderId = "order-9", productId = "corterm.pro.month" }
                }
            });
        });
        using var statusKey = ECDsa.Create();
        var validator = new HuaweiIapValidator(MakeOptions(statusKey), new HttpClient(handler),
            NullLogger<HuaweiIapValidator>.Instance);

        var verified = await validator.VerifySubscriptionJwsAsync(jws, "corterm.pro.month", CancellationToken.None);

        verified.PurchaseToken.Should().Be("sub-token");
        verified.PurchaseOrderId.Should().Be("order-9");
        verified.ProductKind.Should().Be(2);
        verified.IsSubscriptionValid.Should().BeTrue();
        capturedBody.Should().Contain("\"purchaseToken\":\"sub-token\"");
        capturedBody.Should().Contain("\"purchaseOrderId\":\"order-9\"");
    }

    [Fact]
    public async Task VerifySubscriptionJwsAsync_BadSignature_IsRejected()
    {
        // x5c 放真实证书，但用另一把私钥签名 → 验签必须失败，且不能发起任何网络请求
        using var real = ECDsa.Create();
        using var other = ECDsa.Create();
        var certB64 = Convert.ToBase64String(BuildCert(real).Export(X509ContentType.Cert));
        var header = Base64Url(Encoding.UTF8.GetBytes(
            $"{{\"alg\":\"ES256\",\"typ\":\"JWT\",\"x5c\":[\"{certB64}\"]}}"));
        var payload = Base64Url(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new Dictionary<string, object>
        {
            ["environment"] = "SANDBOX",
            ["applicationId"] = AppId,
            ["packageName"] = "top.rwecho.cortexterminal",
            ["lastSubscriptionStatus"] = new Dictionary<string, object>
            {
                ["subscriptionId"] = "sub-1",
                ["purchaseToken"] = "sub-token",
                ["status"] = "1"
            }
        })));
        var signature = other.SignData(Encoding.UTF8.GetBytes($"{header}.{payload}"), HashAlgorithmName.SHA256);
        var jws = $"{header}.{payload}.{Base64Url(signature)}";

        var handler = new StubHandler((_, _) => Json(new { responseCode = "0" }));
        var validator = new HuaweiIapValidator(MakeOptions(ECDsa.Create()), new HttpClient(handler),
            NullLogger<HuaweiIapValidator>.Instance);

        var act = () => validator.VerifySubscriptionJwsAsync(jws, "corterm.pro.month", CancellationToken.None);
        await act.Should().ThrowAsync<IapReceiptInvalidException>();
        handler.Requests.Should().BeEmpty();
    }

    [Fact]
    public async Task VerifySubscriptionJwsAsync_DifferentApp_IsRejected()
    {
        using var signingKey = ECDsa.Create();
        var (jws, payload) = BuildSubscriptionJws(signingKey, "sub-token", "order-9");
        // 篡改 applicationId 后需要重新签名，此处直接换一个 payload 应用ID并保持原签名即可触发拒绝
        payload = payload.Replace($"\"applicationId\":\"{AppId}\"", "\"applicationId\":\"other-app\"");
        jws = SignJws(signingKey, payload);
        var handler = new StubHandler((_, _) => Json(new { responseCode = "0" }));
        var validator = new HuaweiIapValidator(MakeOptions(ECDsa.Create()), new HttpClient(handler),
            NullLogger<HuaweiIapValidator>.Instance);

        var act = () => validator.VerifySubscriptionJwsAsync(jws, "corterm.pro.month", CancellationToken.None);
        await act.Should().ThrowAsync<IapReceiptInvalidException>();
        handler.Requests.Should().BeEmpty();
    }

    [Fact]
    public async Task VerifySubscriptionJwsAsync_InactiveSubscription_IsRejected()
    {
        using var signingKey = ECDsa.Create();
        var (jws, _) = BuildSubscriptionJws(signingKey, "sub-token", "order-9");
        var handler = new StubHandler((_, _) => Json(new
        {
            responseCode = "0",
            environment = "SANDBOX",
            applicationId = AppId,
            packageName = "top.rwecho.cortexterminal",
            lastSubscriptionStatus = new
            {
                subscriptionId = "sub-1",
                purchaseToken = "sub-token",
                status = "2",
                expiresTime = DateTimeOffset.UtcNow.AddDays(-1).ToUnixTimeMilliseconds(),
                lastPurchaseOrder = new { orderId = "order-9", productId = "corterm.pro.month" }
            }
        }));
        var validator = new HuaweiIapValidator(MakeOptions(ECDsa.Create()), new HttpClient(handler),
            NullLogger<HuaweiIapValidator>.Instance);

        var act = () => validator.VerifySubscriptionJwsAsync(jws, "corterm.pro.month", CancellationToken.None);
        await act.Should().ThrowAsync<IapReceiptInvalidException>();
    }

    private static (string Jws, string PayloadJson) BuildSubscriptionJws(
        ECDsa key, string purchaseToken, string orderId)
    {
        var payload = JsonSerializer.Serialize(new Dictionary<string, object>
        {
            ["environment"] = "SANDBOX",
            ["applicationId"] = AppId,
            ["packageName"] = "top.rwecho.cortexterminal",
            ["subGroupId"] = "group-1",
            ["lastSubscriptionStatus"] = new Dictionary<string, object>
            {
                ["subscriptionId"] = "sub-1",
                ["purchaseToken"] = purchaseToken,
                ["status"] = "1",
                ["expiresTime"] = DateTimeOffset.UtcNow.AddDays(30).ToUnixTimeMilliseconds(),
                ["lastPurchaseOrder"] = new Dictionary<string, object>
                {
                    ["orderId"] = orderId,
                    ["productId"] = "corterm.pro.month"
                }
            }
        });
        return (SignJws(key, payload), payload);
    }

    private static string SignJws(ECDsa key, string payloadJson)
    {
        var header = Base64Url(Encoding.UTF8.GetBytes("{\"alg\":\"ES256\",\"typ\":\"JWT\",\"x5c\":[\"" +
            Convert.ToBase64String(BuildCert(key).Export(X509ContentType.Cert)) + "\"]}"));
        var payload = Base64Url(Encoding.UTF8.GetBytes(payloadJson));
        var signature = key.SignData(Encoding.UTF8.GetBytes($"{header}.{payload}"), HashAlgorithmName.SHA256);
        return $"{header}.{payload}.{Base64Url(signature)}";
    }

    private static X509Certificate2 BuildCert(ECDsa key)
    {
        var request = new CertificateRequest("CN=corterm-test", key, HashAlgorithmName.SHA256);
        return request.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddYears(1));
    }

    private static IapOptions MakeOptions(ECDsa key) => new()
    {
        Huawei = new HuaweiIapOptions
        {
            ClientId = AppId,
            RootUrl = RootUrl,
            IssuerId = "issuer-1",
            KeyId = "kid-1",
            SubscriptionPrivateKeyP8 = ExportP8(key),
            BundleName = "top.rwecho.cortexterminal"
        }
    };

    private static string ExportP8(ECDsa key)
    {
        var der = key.ExportPkcs8PrivateKey();
        var base64 = Convert.ToBase64String(der);
        return "-----BEGIN PRIVATE KEY-----\n" + base64 + "\n-----END PRIVATE KEY-----";
    }

    private static JsonDocument DecodeJson(string base64Url)
    {
        var padded = base64Url.Replace('-', '+').Replace('_', '/');
        var padding = (4 - padded.Length % 4) % 4;
        var json = Encoding.UTF8.GetString(Convert.FromBase64String(padded.PadRight(padded.Length + padding, '=')));
        return JsonDocument.Parse(json);
    }

    private static string Base64Url(byte[] value) =>
        Convert.ToBase64String(value).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private static HttpResponseMessage Json<T>(T body) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json")
    };

    private sealed class StubHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, string, HttpResponseMessage> _respond;
        public List<HttpRequestMessage> Requests { get; } = [];
        public StubHandler(Func<HttpRequestMessage, string, HttpResponseMessage> respond) => _respond = respond;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken);
            Requests.Add(request);
            return _respond(request, body);
        }
    }
}
