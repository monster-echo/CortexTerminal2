using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace CortexTerminal.Gateway.Membership;

public sealed record GoogleVerifiedPurchase(string Token, string OrderId, string ProductId, long? ExpiresMs, bool Active, bool NeedsAcknowledgement);

/// Server-to-server verification; no entitlement fields are accepted from the client.
public sealed class GooglePlayValidator(IapOptions options, HttpClient http)
{
    public async Task<GoogleVerifiedPurchase> VerifyAsync(string token, string productId, string userId, CancellationToken ct, bool allowInactive = false)
    {
        var config = options.Google;
        var plan = config.PlanCode(productId);
        if (plan is null || string.IsNullOrWhiteSpace(token) || token.Length > 4096)
            throw new IapReceiptInvalidException("Google purchase token or product is invalid.");
        if (!config.IsConfigured)
            throw new IapReceiptInvalidException("Google Play verification is not configured.");
        var package = Uri.EscapeDataString(config.PackageName);
        var purchaseToken = Uri.EscapeDataString(token);
        var subscription = plan != PlanCodes.ProLifetime;
        var path = subscription
            ? $"applications/{package}/purchases/subscriptionsv2/tokens/{purchaseToken}"
            : $"applications/{package}/purchases/products/{Uri.EscapeDataString(productId)}/tokens/{purchaseToken}";
        using var request = new HttpRequestMessage(HttpMethod.Get, "https://androidpublisher.googleapis.com/androidpublisher/v3/" + path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", await AccessToken(ct));
        using var response = await http.SendAsync(request, ct);
        if (!response.IsSuccessStatusCode)
            throw new IapReceiptInvalidException("Google Play could not verify this purchase.");
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
        var data = document.RootElement;
        if (!config.AllowTestPurchases && (data.TryGetProperty("testPurchase", out _) ||
            (data.TryGetProperty("purchaseType", out var purchaseType) && purchaseType.GetInt32() == 0)))
            throw new IapReceiptInvalidException("Google Play test purchases are disabled.");
        bool active;
        bool needsAcknowledgement;
        string? account;
        long? expires = null;
        string? order;
        if (subscription)
        {
            var state = data.GetProperty("subscriptionState").GetString();
            needsAcknowledgement = String(data, "acknowledgementState") == "ACKNOWLEDGEMENT_STATE_PENDING";
            active = state is "SUBSCRIPTION_STATE_ACTIVE" or "SUBSCRIPTION_STATE_IN_GRACE_PERIOD" or "SUBSCRIPTION_STATE_CANCELED";
            var item = data.GetProperty("lineItems").EnumerateArray().FirstOrDefault(i => String(i, "productId") == productId);
            if (item.ValueKind == JsonValueKind.Undefined || !DateTimeOffset.TryParse(String(item, "expiryTime"), out var expiry))
                throw new IapReceiptInvalidException("Google subscription product or expiry is invalid.");
            active = active && expiry > DateTimeOffset.UtcNow;
            expires = expiry.ToUnixTimeMilliseconds();
            order = String(item, "latestSuccessfulOrderId") ?? String(data, "latestOrderId");
            account = data.TryGetProperty("externalAccountIdentifiers", out var identifiers)
                ? String(identifiers, "obfuscatedExternalAccountId") : null;
        }
        else
        {
            if (!data.TryGetProperty("purchaseState", out var state))
                throw new IapReceiptInvalidException("Google purchase state is missing.");
            active = state.GetInt32() == 0;
            needsAcknowledgement = data.TryGetProperty("acknowledgementState", out var acknowledgement) && acknowledgement.GetInt32() == 0;
            order = String(data, "orderId");
            account = String(data, "obfuscatedExternalAccountId");
        }
        if (!active && !allowInactive)
            throw new IapReceiptInvalidException("Google purchase is not active.");
        var expectedAccount = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(userId))).ToLowerInvariant();
        if (account is not null && account != expectedAccount)
            throw new IapReceiptInvalidException("Google purchase belongs to another account.");
        if (string.IsNullOrWhiteSpace(order)) throw new IapReceiptInvalidException("Google order id is missing.");
        // Keep the raw token out of persistence and audit logs; it is a credential.
        var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token))).ToLowerInvariant();
        return new GoogleVerifiedPurchase(key, order, productId, expires, active, needsAcknowledgement);
    }

    public async Task AcknowledgeAsync(string rawToken, GoogleVerifiedPurchase purchase, CancellationToken ct)
    {
        if (!purchase.Active || !purchase.NeedsAcknowledgement) return;
        var kind = options.Google.PlanCode(purchase.ProductId) == PlanCodes.ProLifetime ? "products" : "subscriptions";
        var path = $"applications/{Uri.EscapeDataString(options.Google.PackageName)}/purchases/{kind}/{Uri.EscapeDataString(purchase.ProductId)}/tokens/{Uri.EscapeDataString(rawToken)}:acknowledge";
        using var request = new HttpRequestMessage(HttpMethod.Post, "https://androidpublisher.googleapis.com/androidpublisher/v3/" + path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", await AccessToken(ct));
        request.Content = new StringContent("{}", Encoding.UTF8, "application/json");
        using var response = await http.SendAsync(request, ct);
        if (!response.IsSuccessStatusCode) throw new HttpRequestException("Google purchase acknowledgement could not be completed. Retry verification.");
    }

    private async Task<string> AccessToken(CancellationToken ct)
    {
        var config = options.Google;
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        static string Encode(byte[] bytes) => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
        var header = Encode(JsonSerializer.SerializeToUtf8Bytes(new { alg = "RS256", typ = "JWT" }));
        var payload = Encode(JsonSerializer.SerializeToUtf8Bytes(new {
            iss = config.ServiceAccountEmail, scope = "https://www.googleapis.com/auth/androidpublisher",
            aud = "https://oauth2.googleapis.com/token", iat = now, exp = now + 3600 }));
        using var rsa = RSA.Create();
        rsa.ImportFromPem(config.PrivateKey.Replace("\\n", "\n"));
        var unsigned = header + "." + payload;
        var assertion = unsigned + "." + Encode(rsa.SignData(Encoding.UTF8.GetBytes(unsigned), HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1));
        using var response = await http.PostAsync("https://oauth2.googleapis.com/token", new FormUrlEncodedContent(new Dictionary<string,string> {
            ["grant_type"] = "urn:ietf:params:oauth:grant-type:jwt-bearer", ["assertion"] = assertion }), ct);
        if (!response.IsSuccessStatusCode) throw new IapReceiptInvalidException("Google Play service authentication failed.");
        using var data = JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
        return String(data.RootElement, "access_token") ?? throw new IapReceiptInvalidException("Google access token is missing.");
    }
    private static string? String(JsonElement data, string key) => data.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
}
