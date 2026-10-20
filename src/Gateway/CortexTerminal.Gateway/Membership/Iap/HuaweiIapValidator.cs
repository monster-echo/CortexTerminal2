using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Gateway.Membership.Iap;

/// <summary>
/// Verifies HarmonyOS IAP Kit purchases through Huawei's server-side APIs
/// (<c>{rootUrl}/order|subscription/harmony/v1/.../status/query</c>).
///
/// Those APIs are authorized with a per-request ES256 JWT signed by the
/// AppGallery Connect in-app purchase server key (Issuer ID + Key ID + .p8),
/// whose payload carries the SHA-256 digest of the exact request body.
/// </summary>
public sealed class HuaweiIapValidator : IHuaweiIapValidator
{
    private const string DefaultRootUrl = "https://iap.cloud.huawei.com";
    private const string JwtAudience = "iap-v1";
    private const int UserCanceled = 1001860000;

    private readonly HuaweiIapOptions _options;
    private readonly HttpClient _http;
    private readonly ILogger<HuaweiIapValidator> _logger;
    private ECDsa? _jwtKey;

    public HuaweiIapValidator(IapOptions options, HttpClient http, ILogger<HuaweiIapValidator> logger)
    {
        _options = options.Huawei;
        _http = http;
        _logger = logger;
    }

    /// <summary>终身买断（非消耗型）：订单状态查询。</summary>
    public Task<HuaweiVerifiedTransaction> VerifyAsync(
        string purchaseToken, string purchaseOrderId, string productId, CancellationToken ct)
        => VerifyOrderAsync(purchaseToken, purchaseOrderId, productId, expectedKind: 1, ct);

    /// <summary>订单状态查询（不限制商品类型，供服务端通知等场景使用）。</summary>
    public async Task<HuaweiVerifiedTransaction> VerifyOrderAsync(
        string purchaseToken, string purchaseOrderId, string productId, int expectedKind, CancellationToken ct)
    {
        ValidateIds(purchaseToken, purchaseOrderId, productId);

        var root = await PostIapAsync("/order/harmony/v1/application/order/status/query",
            new { purchaseToken, purchaseOrderId }, ct);
        var status = ExpectSuccess(root, "order");

        // 响应是 JWS 包装的订单数据（jwsPurchaseOrder），需解码验签后才能读取字段。
        var orderJws = GetString(status, "jwsPurchaseOrder");
        if (string.IsNullOrWhiteSpace(orderJws))
            throw new IapReceiptInvalidException("Huawei order status query returned no signed purchase order.");

        var jws = DecodeJws(orderJws);
        VerifyJwsSignature(jws);

        var verifiedProductId = GetString(jws.Payload, "productId");
        var verifiedToken = GetString(jws.Payload, "purchaseToken");
        var verifiedOrderId = GetString(jws.Payload, "purchaseOrderId");
        var applicationId = GetString(jws.Payload, "applicationId");
        var productType = GetString(jws.Payload, "productType");

        _logger.LogInformation(
            "Huawei order JWS verified (productId {ProductId}, environment {Environment}, price {Price}).",
            verifiedProductId, GetString(jws.Payload, "environment"), GetString(jws.Payload, "price"));

        if (!string.Equals(applicationId, _options.ClientId, StringComparison.Ordinal))
            throw new IapReceiptInvalidException("Huawei order belongs to a different app.");
        if (!string.Equals(verifiedProductId, productId, StringComparison.Ordinal)
            || !string.Equals(verifiedToken, purchaseToken, StringComparison.Ordinal)
            || !string.Equals(verifiedOrderId, purchaseOrderId, StringComparison.Ordinal))
            throw new IapReceiptInvalidException("Huawei verified order does not match the request.");
        if (productType != "1")
            throw new IapReceiptInvalidException("Huawei lifetime membership must be a non-consumable product.");
        if (expectedKind != 0 && 1 != expectedKind)
            throw new IapReceiptInvalidException(
                $"Huawei purchase is of kind 1 (non-consumable), not the expected kind {expectedKind}.");

        return new HuaweiVerifiedTransaction(
            verifiedToken ?? purchaseToken, verifiedOrderId ?? purchaseOrderId,
            verifiedProductId ?? productId, 0, 1, null, null);
    }

    private sealed record HuaweiJws(string HeaderJson, JsonElement Payload, byte[] Signature, byte[] SigningInput);

    private static HuaweiJws DecodeJws(string jws)
    {
        var parts = jws.Split('.');
        if (parts.Length != 3)
            throw new IapReceiptInvalidException("Huawei JWS is malformed.");
        try
        {
            var headerJson = Encoding.UTF8.GetString(Base64UrlDecode(parts[0]));
            using var payloadDoc = JsonDocument.Parse(Encoding.UTF8.GetString(Base64UrlDecode(parts[1])));
            var signature = Base64UrlDecode(parts[2]);
            var signingInput = Encoding.ASCII.GetBytes($"{parts[0]}.{parts[1]}");
            return new HuaweiJws(headerJson, payloadDoc.RootElement.Clone(), signature, signingInput);
        }
        catch (FormatException ex)
        {
            throw new IapReceiptInvalidException("Huawei JWS is malformed.", ex);
        }
        catch (JsonException ex)
        {
            throw new IapReceiptInvalidException("Huawei JWS is malformed.", ex);
        }
    }

    private static void VerifyJwsSignature(HuaweiJws jws)
    {
        using var header = JsonDocument.Parse(jws.HeaderJson);
        if (GetString(header.RootElement, "alg") != "ES256")
            throw new IapReceiptInvalidException("Huawei JWS uses an unsupported signature algorithm.");
        if (!header.RootElement.TryGetProperty("x5c", out var x5c)
            || x5c.ValueKind != JsonValueKind.Array || x5c.GetArrayLength() == 0)
            throw new IapReceiptInvalidException("Huawei JWS carries no certificate chain.");

        X509Certificate2 leaf;
        try
        {
            leaf = X509CertificateLoader.LoadCertificate(Convert.FromBase64String(x5c[0].GetString() ?? ""));
        }
        catch (Exception ex) when (ex is FormatException or CryptographicException)
        {
            throw new IapReceiptInvalidException("Huawei JWS certificate chain is malformed.", ex);
        }

        using var ecdsa = leaf.GetECDsaPublicKey();
        if (ecdsa is null)
            throw new IapReceiptInvalidException("Huawei JWS certificate is not an EC certificate.");
        if (!ecdsa.VerifyData(jws.SigningInput, jws.Signature, HashAlgorithmName.SHA256))
            throw new IapReceiptInvalidException("Huawei JWS signature is invalid.");
    }

    /// <summary>
    /// 自动续期订阅：先验客户端上报的订阅 JWS（ES256），取出订阅状态后，
    /// 再向华为查询最新状态，确认订阅仍在生效中。
    /// </summary>
    public async Task<HuaweiVerifiedTransaction> VerifySubscriptionJwsAsync(
        string jws, string productId, CancellationToken ct)
    {
        // 订阅路径的 token / 订单号取自 JWS，这里只校验商品 ID。
        if (string.IsNullOrWhiteSpace(productId) || productId.Length > 256)
            throw new IapReceiptInvalidException("Huawei product id is missing or malformed.");
        if (HuaweiProductIds.ToPlanCode(_options, productId) is null)
            throw new IapReceiptInvalidException("Huawei product id is not configured for membership.");

        var parts = jws.Split('.');
        if (parts.Length != 3)
            throw new IapReceiptInvalidException("Huawei subscription JWS is malformed.");

        string headerJson;
        string payloadJson;
        byte[] signature;
        try
        {
            headerJson = Encoding.UTF8.GetString(Base64UrlDecode(parts[0]));
            payloadJson = Encoding.UTF8.GetString(Base64UrlDecode(parts[1]));
            signature = Base64UrlDecode(parts[2]);
        }
        catch (FormatException ex)
        {
            throw new IapReceiptInvalidException("Huawei subscription JWS is malformed.", ex);
        }

        using var header = JsonDocument.Parse(headerJson);
        if (GetString(header.RootElement, "alg") != "ES256")
            throw new IapReceiptInvalidException("Huawei subscription JWS uses an unsupported signature algorithm.");

        using var payload = JsonDocument.Parse(payloadJson);
        var environment = GetString(payload.RootElement, "environment");
        var applicationId = GetString(payload.RootElement, "applicationId");
        var packageName = GetString(payload.RootElement, "packageName");

        // JWS 的签名输入是 base64url(header) + "." + base64url(payload) 的 ASCII 字节，
        // 不是解码后的 JSON。
        var signingInput = Encoding.ASCII.GetBytes($"{parts[0]}.{parts[1]}");
        if (!VerifyEs256WithX5cLeaf(headerJson, signingInput, signature))
            throw new IapReceiptInvalidException("Huawei subscription JWS signature is invalid.");
        _logger.LogInformation(
            "Huawei subscription JWS verified (environment {Environment}, appId {ApplicationId}, package {Package}).",
            environment, applicationId, packageName);

        if (!string.Equals(applicationId, _options.ClientId, StringComparison.Ordinal))
            throw new IapReceiptInvalidException("Huawei subscription JWS belongs to a different app.");
        if (!string.IsNullOrWhiteSpace(_options.BundleName)
            && !string.Equals(packageName, _options.BundleName, StringComparison.Ordinal))
            throw new IapReceiptInvalidException("Huawei subscription JWS has an unexpected package name.");

        if (!payload.RootElement.TryGetProperty("lastSubscriptionStatus", out var reported)
            || reported.ValueKind != JsonValueKind.Object)
            throw new IapReceiptInvalidException("Huawei subscription JWS has no subscription status.");

        var jwsSubscriptionId = GetString(reported, "subscriptionId");
        var jwsToken = GetString(reported, "purchaseToken");
        var jwsOrderId = default(string);
        if (reported.TryGetProperty("lastPurchaseOrder", out var order) && order.ValueKind == JsonValueKind.Object)
            jwsOrderId = GetString(order, "orderId");

        if (string.IsNullOrWhiteSpace(jwsToken) || string.IsNullOrWhiteSpace(jwsSubscriptionId))
            throw new IapReceiptInvalidException(
                "Huawei subscription JWS is missing the purchase token or subscription id.");

        return await VerifySubscriptionStatusAsync(
            jwsOrderId ?? string.Empty, jwsToken, productId, ct);
    }

    /// <summary>订阅状态查询：向华为确认订阅当前仍生效（而不是只信客户端带来的快照）。</summary>
    public async Task<HuaweiVerifiedTransaction> VerifySubscriptionStatusAsync(
        string purchaseOrderId, string purchaseToken, string productId, CancellationToken ct)
    {
        ValidateIds(purchaseToken, purchaseOrderId, productId);

        var root = await PostIapAsync("/subscription/harmony/v1/application/subscription/status/query",
            new { purchaseOrderId, purchaseToken }, ct);
        var status = ExpectSuccess(root, "subscription");

        if (!status.TryGetProperty("lastSubscriptionStatus", out var latest)
            || latest.ValueKind != JsonValueKind.Object)
            throw new IapReceiptInvalidException("Huawei subscription status query returned no active status.");

        var liveStatus = GetString(latest, "status");
        var expiresMs = GetLong(latest, "expiresTime");
        var verifiedProductId = default(string);
        if (latest.TryGetProperty("lastPurchaseOrder", out var liveOrder) && liveOrder.ValueKind == JsonValueKind.Object)
            verifiedProductId = GetString(liveOrder, "productId");

        _logger.LogInformation(
            "Huawei subscription status queried (subscriptionId {SubscriptionId}, status {Status}).",
            GetString(latest, "subscriptionId"), liveStatus);

        if (liveStatus != "1")
            throw new IapReceiptInvalidException("Huawei subscription is not currently active.");
        if (expiresMs is null || expiresMs <= DateTimeOffset.UtcNow.ToUnixTimeMilliseconds())
            throw new IapReceiptInvalidException("Huawei subscription has expired.");
        if (!string.IsNullOrWhiteSpace(verifiedProductId)
            && !string.Equals(verifiedProductId, productId, StringComparison.Ordinal))
            throw new IapReceiptInvalidException(
                $"Huawei subscription is for {verifiedProductId}, not {productId}.");

        return new HuaweiVerifiedTransaction(
            purchaseToken, purchaseOrderId, productId, 0, 2, expiresMs, true);
    }

    private void ValidateIds(string purchaseToken, string purchaseOrderId, string productId)
    {
        if (string.IsNullOrWhiteSpace(purchaseToken) || purchaseToken.Length > 256)
            throw new IapReceiptInvalidException("Huawei purchase token is missing or malformed.");
        if (string.IsNullOrWhiteSpace(purchaseOrderId) || purchaseOrderId.Length > 256)
            throw new IapReceiptInvalidException("Huawei purchase order id is missing or malformed.");
        if (string.IsNullOrWhiteSpace(productId) || productId.Length > 256)
            throw new IapReceiptInvalidException("Huawei product id is missing or malformed.");
        if (HuaweiProductIds.ToPlanCode(_options, productId) is null)
            throw new IapReceiptInvalidException("Huawei product id is not configured for membership.");
    }

    private async Task<JsonElement> PostIapAsync(string path, object body, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(_options.RootUrl))
            throw new IapReceiptInvalidException("Huawei IAP server root url is not configured.");
        if (string.IsNullOrWhiteSpace(_options.IssuerId) || string.IsNullOrWhiteSpace(_options.KeyId)
            || string.IsNullOrWhiteSpace(_options.SubscriptionPrivateKeyP8))
            throw new IapReceiptInvalidException(
                "Huawei IAP server key is not configured (issuer id, key id and .p8 private key are required).");

        var bodyJson = JsonSerializer.Serialize(body);
        var jwt = CreateRequestJwt(bodyJson);

        using var request = new HttpRequestMessage(HttpMethod.Post, $"{_options.RootUrl.TrimEnd('/')}{path}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", jwt);
        request.Content = new StringContent(bodyJson, Encoding.UTF8, "application/json");
        using var response = await _http.SendAsync(request, ct);
        var json = await response.Content.ReadAsStringAsync(ct);
        _logger.LogInformation("Huawei IAP {Path} -> HTTP {Status} body: {Body}", path,
            (int)response.StatusCode, json);
        if (!response.IsSuccessStatusCode)
            throw new IapReceiptInvalidException($"Huawei IAP verification service returned HTTP {(int)response.StatusCode}.");
        try
        {
            using var document = JsonDocument.Parse(json);
            return document.RootElement.Clone();
        }
        catch (JsonException ex)
        {
            throw new IapReceiptInvalidException("Huawei IAP verification response was malformed.", ex);
        }
    }

    private static JsonElement ExpectSuccess(JsonElement root, string kind)
    {
        var responseCode = GetString(root, "responseCode");
        if (!string.Equals(responseCode, "0", StringComparison.Ordinal))
            throw new IapReceiptInvalidException(
                $"Huawei IAP rejected {kind} verification (code {responseCode ?? "unknown"}).");
        return root;
    }

    /// <summary>ES256 JWT：payload 带 aud=iap-v1 / aid / digest(请求体 SHA-256)，有效期 ≤1 小时。</summary>
    private string CreateRequestJwt(string bodyJson)
    {
        var now = DateTimeOffset.UtcNow;
        var digest = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(bodyJson))).ToLowerInvariant();

        var header = Base64UrlEncode(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new
        {
            alg = "ES256",
            typ = "JWT",
            kid = _options.KeyId
        })));
        var payload = Base64UrlEncode(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new
        {
            iss = _options.IssuerId,
            aud = JwtAudience,
            iat = now.ToUnixTimeSeconds(),
            exp = now.AddMinutes(30).ToUnixTimeSeconds(),
            aid = _options.ClientId,
            digest
        })));

        using var ecdsa = JwtKey();
        var signature = ecdsa.SignData(Encoding.UTF8.GetBytes($"{header}.{payload}"), HashAlgorithmName.SHA256);
        return $"{header}.{payload}.{Base64UrlEncode(signature)}";
    }

    private ECDsa JwtKey()
    {
        if (_jwtKey is not null) return _jwtKey;
        // 兼容 env 里以字面 \n 存储的 PEM（与 AppleOAuth__PrivateKey 同一约定）
        var pem = _options.SubscriptionPrivateKeyP8.Replace("\\n", "\n").Trim();
        var key = ECDsa.Create();
        try
        {
            key.ImportFromPem(pem);
        }
        catch (Exception ex)
        {
            throw new IapReceiptInvalidException("Huawei IAP server key could not be parsed.", ex);
        }
        _jwtKey = key;
        return key;
    }

    /// <summary>JWS 的 x5c 链叶子证书公钥验 ES256 签名。</summary>
    private static bool VerifyEs256WithX5cLeaf(string headerJson, byte[] data, byte[] signature)
    {
        try
        {
            using var header = JsonDocument.Parse(headerJson);
            if (!header.RootElement.TryGetProperty("x5c", out var x5c)
                || x5c.ValueKind != JsonValueKind.Array || x5c.GetArrayLength() == 0)
                return false;
            var leaf = X509CertificateLoader.LoadCertificate(Convert.FromBase64String(x5c[0].GetString() ?? ""));
            using var ecdsa = leaf.GetECDsaPublicKey();
            if (ecdsa is null) return false;
            return ecdsa.VerifyData(data, signature, HashAlgorithmName.SHA256);
        }
        catch (CryptographicException) { return false; }
        catch (FormatException) { return false; }
        catch (JsonException) { return false; }
    }

    private static byte[] Base64UrlDecode(string value)
    {
        var padded = value.Trim().Replace('-', '+').Replace('_', '/');
        var padding = (4 - padded.Length % 4) % 4;
        return Convert.FromBase64String(padded.PadRight(padded.Length + padding, '='));
    }

    private static string Base64UrlEncode(byte[] value)
    {
        return Convert.ToBase64String(value).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }

    private static string? GetString(JsonElement obj, string name)
    {
        if (!obj.TryGetProperty(name, out var value) || value.ValueKind == JsonValueKind.Null) return null;
        return value.ValueKind == JsonValueKind.String ? value.GetString() : value.ToString();
    }

    private static long? GetLong(JsonElement obj, string name)
    {
        if (!obj.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.Number) return null;
        return value.TryGetInt64(out var result) ? result : null;
    }

    private static int GetInt(JsonElement obj, string name) =>
        GetLong(obj, name) is long result ? (int)result : 0;

    private static bool? GetBool(JsonElement obj, string name)
    {
        if (!obj.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.True
            && value.ValueKind != JsonValueKind.False) return null;
        return value.GetBoolean();
    }
}

internal static class HuaweiProductIds
{
    public static string? ToPlanCode(HuaweiIapOptions options, string productId)
    {
        if (productId == options.ProMonthProductId) return PlanCodes.ProMonth;
        if (productId == options.ProYearProductId) return PlanCodes.ProYear;
        if (productId == options.ProLifetimeProductId) return PlanCodes.ProLifetime;
        return null;
    }
}
