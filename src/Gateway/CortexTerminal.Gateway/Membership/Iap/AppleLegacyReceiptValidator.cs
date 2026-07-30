using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CortexTerminal.Gateway.Membership.Iap;

/// <summary>
/// Legacy StoreKit 1 receipt validator backed by Apple's deprecated-but-still-supported
/// <c>/verifyReceipt</c> endpoint. Used by the .NET MAUI iOS client which can only talk to
/// StoreKit 1 (<c>Plugin.InAppBilling</c>) and therefore produces a base64 legacy receipt,
/// not a StoreKit 2 JWS. Mirrors the field-extraction contract of <see cref="AppleReceiptValidator"/>
/// so the same <see cref="AppleVerifiedTransaction"/> feeds
/// <see cref="MembershipService.GrantFromIapAsync"/>.
///
/// Verification flow (standard Apple best practice):
/// 1. Always POST to the Production endpoint first.
/// 2. If Apple replies status <c>21007</c> ("This receipt is a sandbox receipt, but it was
///    sent to the production service for verification"), retry against Sandbox — App Review
///    and dev builds ship sandbox receipts.
/// 3. Any other non-zero status -> <see cref="IapReceiptInvalidException"/>.
/// 4. From the validated response pick the LAST entry of <c>latest_receipt_info</c>
///    (auto-renewable subscriptions — Apple appends renewals) or <c>receipt.in_app</c>
///    (one-time purchases) and map <c>original_transaction_id</c> / <c>product_id</c> /
///    <c>expires_date_ms</c> (absent/0 for non-consumables -> null).
/// </summary>
public sealed class AppleLegacyReceiptValidator : IAppleLegacyReceiptValidator
{
    private const string ProductionUrl = "https://buy.itunes.apple.com/verifyReceipt";
    private const string SandboxUrl = "https://sandbox.itunes.apple.com/verifyReceipt";

    // Apple documents status 21007 as "receipt is a sandbox receipt, but it was sent to the
    // production service for verification". On this status we transparently retry Sandbox.
    private const int StatusSandboxReceiptOnProduction = 21007;
    private const int StatusOk = 0;

    // Every (de)serialized property carries an explicit [JsonPropertyName] matching Apple's
    // snake_case response, so we serialize with default (untransformed) naming. AllowReadingFromString
    // lets us parse expires_date_ms whether Apple ships it as a JSON number or a quoted string.
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    private readonly IapOptions _iap;
    private readonly HttpClient _http;
    private readonly ILogger<AppleLegacyReceiptValidator> _logger;

    public AppleLegacyReceiptValidator(IapOptions iap, HttpClient http, ILogger<AppleLegacyReceiptValidator> logger)
    {
        _iap = iap;
        _http = http;
        _logger = logger;
    }

    public async Task<AppleVerifiedTransaction> VerifyAsync(string receiptDataBase64, CancellationToken ct)
    {
        // Apple's request body: snake_case, password = the app's shared secret.
        var requestBody = new VerifyReceiptRequest(
            ReceiptData: receiptDataBase64,
            Password: _iap.Apple.SharedSecret,
            ExcludeOldTransactions: true
        );

        var prod = await PostAsync(ProductionUrl, requestBody, ct);
        var status = prod.Status;

        if (status == StatusSandboxReceiptOnProduction)
        {
            _logger.LogInformation("Apple /verifyReceipt returned 21007; retrying against sandbox endpoint");
            var sandbox = await PostAsync(SandboxUrl, requestBody, ct);
            status = sandbox.Status;
            prod = sandbox;
        }

        if (status != StatusOk)
        {
            throw new IapReceiptInvalidException(
                $"Apple /verifyReceipt rejected the receipt (status {status})."
            );
        }

        return ExtractTransaction(prod);
    }

    private async Task<VerifyReceiptResponse> PostAsync(string url, VerifyReceiptRequest body, CancellationToken ct)
    {
        using var resp = await _http.PostAsJsonAsync(url, body, JsonOptions, ct);
        // PostAsJsonAsync throws HttpRequestException on non-2xx, but /verifyReceipt returns 200 even
        // for invalid receipts (carrying the error in the `status` field). We therefore do not need
        // an explicit EnsureSuccessStatusCode branch — a transport-level failure surfaces as-is.
        var parsed = await resp.Content.ReadFromJsonAsync<VerifyReceiptResponse>(JsonOptions, ct);
        if (parsed is null)
        {
            throw new IapReceiptInvalidException("Apple /verifyReceipt returned an empty response body.");
        }
        return parsed;
    }

    private static AppleVerifiedTransaction ExtractTransaction(VerifyReceiptResponse resp)
    {
        // latest_receipt_info holds the full renewal history for auto-renewable subscriptions;
        // the last element is the current/active period. For non-renewing purchases that array is
        // absent and we fall back to the last entry of receipt.in_app.
        InAppEntry? entry = null;
        var latest = resp.LatestReceiptInfo;
        var inApp = resp.Receipt?.InApp;

        if (latest is { Count: > 0 })
        {
            entry = latest[latest.Count - 1];
        }
        else if (inApp is { Count: > 0 })
        {
            entry = inApp[inApp.Count - 1];
        }

        if (entry is null)
        {
            throw new IapReceiptInvalidException("Apple /verifyReceipt response contained no in-app purchase entries.");
        }

        // expires_date_ms is a long (ms) for auto-renewable subscriptions; absent or 0 for
        // non-consumables / consumables. We surface those as null so GrantFromIapAsync treats
        // the purchase as never-expiring.
        long? expiresMs = entry.ExpiresDateMs is > 0 ? entry.ExpiresDateMs : null;

        return new AppleVerifiedTransaction(
            OriginalTransactionId: entry.OriginalTransactionId,
            ProductId: entry.ProductId,
            ExpiresDateMs: expiresMs,
            // The legacy /verifyReceipt response does not carry a per-transaction `type` field.
            // We infer the type from the presence of an expiry: a non-null expiry means an
            // auto-renewable subscription; otherwise it is a non-consumable lifetime purchase
            // (the only two product families CortexTerminal ships).
            Type: expiresMs is null ? "Non-Consumable" : "Auto-Renewable Subscription"
        );
    }

    private sealed record VerifyReceiptRequest(
        [property: JsonPropertyName("receipt-data")] string ReceiptData,
        [property: JsonPropertyName("password")] string Password,
        [property: JsonPropertyName("exclude-old-transactions")] bool ExcludeOldTransactions
    );

    private sealed record VerifyReceiptResponse(
        [property: JsonPropertyName("status")] int Status,
        [property: JsonPropertyName("receipt")] ReceiptPayload? Receipt,
        [property: JsonPropertyName("latest_receipt_info")] List<InAppEntry>? LatestReceiptInfo
    );

    private sealed record ReceiptPayload(
        [property: JsonPropertyName("in_app")] List<InAppEntry>? InApp
    );

    private sealed record InAppEntry(
        [property: JsonPropertyName("original_transaction_id")] string OriginalTransactionId,
        [property: JsonPropertyName("product_id")] string ProductId,
        // Apple ships expires_date_ms as a stringified number in some payloads; JsonNumberHandling
        // lets us read it whether the token is a number or a quoted number.
        [property: JsonPropertyName("expires_date_ms")]
        [property: JsonNumberHandling(JsonNumberHandling.AllowReadingFromString | JsonNumberHandling.WriteAsString)]
        long ExpiresDateMs
    );
}
