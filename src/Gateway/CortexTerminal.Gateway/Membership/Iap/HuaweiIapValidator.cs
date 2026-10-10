using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Net.Http.Json;

namespace CortexTerminal.Gateway.Membership.Iap;

/// <summary>
/// Verifies Huawei IAP purchases server-to-server, then verifies Huawei's signed
/// purchaseTokenData before returning any entitlement-bearing fields.
/// </summary>
public sealed class HuaweiIapValidator : IHuaweiIapValidator
{
    private readonly HuaweiIapOptions _options;
    private readonly HttpClient _http;
    private readonly SemaphoreSlim _tokenLock = new(1, 1);
    private string? _accessToken;
    private DateTimeOffset _accessTokenExpiresUtc;

    public HuaweiIapValidator(IapOptions options, HttpClient http)
    {
        _options = options.Huawei;
        _http = http;
    }

    public async Task<HuaweiVerifiedTransaction> VerifyAsync(
        string purchaseToken, string productId, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(purchaseToken) || purchaseToken.Length > 4096)
            throw new IapReceiptInvalidException("Huawei purchase token is missing or malformed.");
        if (string.IsNullOrWhiteSpace(productId) || productId.Length > 256)
            throw new IapReceiptInvalidException("Huawei product id is missing or malformed.");

        var planCode = HuaweiProductIds.ToPlanCode(_options, productId);
        if (planCode is null)
            throw new IapReceiptInvalidException("Huawei product id is not configured for membership.");

        var isSubscription = planCode is PlanCodes.ProMonth or PlanCodes.ProYear;
        var rootUrl = isSubscription ? _options.SubscriptionRootUrl : _options.OrderRootUrl;
        if (!Uri.TryCreate(rootUrl, UriKind.Absolute, out var root) || root.Scheme != Uri.UriSchemeHttps)
            throw new IapReceiptInvalidException("Huawei IAP server is not configured for this product type.");
        if (string.IsNullOrWhiteSpace(_options.PaymentPublicKey))
            throw new IapReceiptInvalidException("Huawei IAP payment public key is not configured.");

        var payload = isSubscription
            ? await PostAsync(rootUrl.TrimEnd('/') + "/sub/applications/v2/purchases/get",
                new { subscriptionId = productId, purchaseToken }, ct)
            : await PostAsync(rootUrl.TrimEnd('/') + "/applications/purchases/tokens/verify",
                new { purchaseToken, productId }, ct);

        var responseCode = GetString(payload, "responseCode");
        if (!string.Equals(responseCode, "0", StringComparison.Ordinal))
            throw new IapReceiptInvalidException($"Huawei IAP rejected purchase verification (code {responseCode ?? "unknown"}).");

        var purchaseData = GetString(payload, "purchaseTokenData");
        var signature = GetString(payload, "dataSignature");
        var algorithm = GetString(payload, "signatureAlgorithm") ?? "SHA256WithRSA";
        if (string.IsNullOrWhiteSpace(purchaseData) || string.IsNullOrWhiteSpace(signature)
            || !VerifySignature(purchaseData, signature, algorithm))
            throw new IapReceiptInvalidException("Huawei purchase verification signature is invalid.");

        using var data = JsonDocument.Parse(purchaseData);
        var rootData = data.RootElement;
        var verifiedProductId = GetString(rootData, "productId");
        var purchaseState = GetInt(rootData, "purchaseState");
        var verifiedToken = GetString(rootData, "purchaseToken");
        var orderId = GetString(rootData, "payOrderId") ?? GetString(rootData, "orderId");
        var kind = GetInt(rootData, "kind");
        var expiryMs = GetLong(rootData, "expirationDate");
        var subValid = GetBool(rootData, "subIsvalid");

        if (!string.Equals(verifiedProductId, productId, StringComparison.Ordinal)
            || !string.Equals(verifiedToken, purchaseToken, StringComparison.Ordinal)
            || string.IsNullOrWhiteSpace(orderId)
            || purchaseState != 0)
            throw new IapReceiptInvalidException("Huawei verified purchase data does not match the request or is not paid.");

        if (isSubscription && (kind != 2 || subValid != true || expiryMs is null || expiryMs <= DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()))
            throw new IapReceiptInvalidException("Huawei subscription is not currently active.");
        if (!isSubscription && kind != 1)
            throw new IapReceiptInvalidException("Huawei lifetime membership must be a non-consumable product.");

        return new HuaweiVerifiedTransaction(
            verifiedToken!, orderId!, verifiedProductId!, purchaseState, kind,
            isSubscription ? expiryMs : null, subValid);
    }

    private async Task<JsonElement> PostAsync(string url, object body, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Basic", BuildAppAtHeader(await GetAccessTokenAsync(ct)));
        request.Content = JsonContent.Create(body);
        using var response = await _http.SendAsync(request, ct);
        var json = await response.Content.ReadAsStringAsync(ct);
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

    private async Task<string> GetAccessTokenAsync(CancellationToken ct)
    {
        if (!string.IsNullOrWhiteSpace(_accessToken) && _accessTokenExpiresUtc > DateTimeOffset.UtcNow.AddMinutes(2))
            return _accessToken;

        await _tokenLock.WaitAsync(ct);
        try
        {
            if (!string.IsNullOrWhiteSpace(_accessToken) && _accessTokenExpiresUtc > DateTimeOffset.UtcNow.AddMinutes(2))
                return _accessToken;
            if (string.IsNullOrWhiteSpace(_options.ClientId) || string.IsNullOrWhiteSpace(_options.ClientSecret))
                throw new IapReceiptInvalidException("Huawei IAP server credentials are not configured.");

            using var request = new HttpRequestMessage(HttpMethod.Post, _options.TokenUrl)
            {
                Content = new FormUrlEncodedContent(new Dictionary<string, string>
                {
                    ["grant_type"] = "client_credentials",
                    ["client_id"] = _options.ClientId,
                    ["client_secret"] = _options.ClientSecret,
                })
            };
            using var response = await _http.SendAsync(request, ct);
            if (!response.IsSuccessStatusCode)
                throw new IapReceiptInvalidException($"Huawei OAuth returned HTTP {(int)response.StatusCode}.");
            using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
            _accessToken = GetString(document.RootElement, "access_token");
            var expiresIn = GetLong(document.RootElement, "expires_in") ?? 3600;
            if (string.IsNullOrWhiteSpace(_accessToken))
                throw new IapReceiptInvalidException("Huawei OAuth response did not include an access token.");
            _accessTokenExpiresUtc = DateTimeOffset.UtcNow.AddSeconds(Math.Max(60, expiresIn));
            return _accessToken;
        }
        catch (JsonException ex)
        {
            throw new IapReceiptInvalidException("Huawei OAuth response was malformed.", ex);
        }
        finally
        {
            _tokenLock.Release();
        }
    }

    internal static string BuildAppAtHeader(string accessToken) =>
        Convert.ToBase64String(Encoding.UTF8.GetBytes($"APPAT:{accessToken}"));

    private bool VerifySignature(string content, string signature, string algorithm)
    {
        try
        {
            using var rsa = RSA.Create();
            rsa.ImportSubjectPublicKeyInfo(Convert.FromBase64String(_options.PaymentPublicKey), out _);
            var padding = algorithm switch
            {
                "SHA256WithRSA" => RSASignaturePadding.Pkcs1,
                "SHA256WithRSA/PSS" => RSASignaturePadding.Pss,
                _ => null,
            };
            return padding is not null && rsa.VerifyData(
                Encoding.UTF8.GetBytes(content), Convert.FromBase64String(signature),
                HashAlgorithmName.SHA256, padding);
        }
        catch (CryptographicException) { return false; }
        catch (FormatException) { return false; }
    }

    private static string? GetString(JsonElement obj, string name)
    {
        if (!obj.TryGetProperty(name, out var value) || value.ValueKind == JsonValueKind.Null) return null;
        return value.ValueKind == JsonValueKind.String ? value.GetString() : value.ToString();
    }

    private static long? GetLong(JsonElement obj, string name)
    {
        if (!obj.TryGetProperty(name, out var value)) return null;
        return value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out var n)
            ? n : long.TryParse(value.ToString(), out n) ? n : null;
    }

    private static int GetInt(JsonElement obj, string name) =>
        (int)(GetLong(obj, name) ?? -1);

    private static bool? GetBool(JsonElement obj, string name)
    {
        if (!obj.TryGetProperty(name, out var value)) return null;
        if (value.ValueKind is JsonValueKind.True or JsonValueKind.False) return value.GetBoolean();
        return bool.TryParse(value.ToString(), out var parsed) ? parsed : null;
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
