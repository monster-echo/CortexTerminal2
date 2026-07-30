using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using CortexTerminal.Mobile.App.Services.Auth;
using CortexTerminal.Mobile.App.Services.Iap;
using CortexTerminal.Mobile.Core.Bridge;
using CortexTerminal.Mobile.Core.Features.Iap;

namespace CortexTerminal.Mobile.App.Services.Bridge;

// Billing bridge: drives an Apple in-app purchase through IapService (StoreKit 1 on iOS via
// Plugin.InAppBilling), then forwards the signed receipt to the gateway
// POST /api/iap/purchase/verify (receiptFormat=legacy) to grant entitlement.
//
// Failure modes are returned as structured { success=false, errorCode, message } payloads so the
// Web UI can branch (user-cancel is a no-op, verify failure shows a retry CTA). We deliberately
// use the `errorCode` key (not `error`) — the bridge runtime (bridge/runtime.ts) auto-rejects any
// payload containing an `error` field, so structured non-fatal outcomes must avoid that key.
public sealed partial class AppBridge
{
    private IIapService? _iapService;
    private AuthService? _billingAuthService;
    private HttpClient? _gatewayHttpClient;

    internal void SetBillingServices(IIapService iapService, AuthService authService, HttpClient gatewayHttpClient)
    {
        _iapService = iapService;
        _billingAuthService = authService;
        _gatewayHttpClient = gatewayHttpClient;
    }

    [BridgeMethod]
    public Task<string> PurchasePlanAsync(string planCode)
    {
        return ExecuteSafeAsync<object>(async () =>
        {
            if (_iapService is null || _gatewayHttpClient is null || _billingAuthService is null)
                throw new InvalidOperationException("Billing services not configured");

            var productId = PlanCodeToAppleProductId(planCode);
            if (productId is null)
                return new { success = false, errorCode = "unknown_plan", message = $"Unknown plan code: {planCode}" };

            IapPurchaseResult purchase;
            try
            {
                purchase = await _iapService.PurchaseAsync(productId, CancellationToken.None);
            }
            catch (IapPurchaseException ex)
            {
                // User cancellation is a normal, non-fatal outcome; other store errors (payment
                // invalid, billing unavailable, ...) are surfaced with their plugin error code so
                // the UI can localize the message.
                return new
                {
                    success = false,
                    errorCode = ex.IsUserCancelled ? "user_cancelled" : "purchase_failed",
                    message = ex.Message,
                };
            }

            return await VerifyPurchaseAsync(purchase);
        });
    }

    [BridgeMethod]
    public Task<string> RestorePurchasesAsync()
    {
        return ExecuteSafeAsync<object>(async () =>
        {
            if (_iapService is null)
                throw new InvalidOperationException("Billing services not configured");

            try
            {
                await _iapService.RestoreAsync(CancellationToken.None);
            }
            catch (IapPurchaseException ex)
            {
                return new { success = false, errorCode = "restore_failed", message = ex.Message };
            }
            // Entitlement is reconciled server-side via Apple App Store Server Notifications V2
            // (POST /api/iap/webhook/apple); the client only needs to know the restore sync ran.
            return new { success = true };
        });
    }

    private async Task<object> VerifyPurchaseAsync(IapPurchaseResult purchase)
    {
        // POST /api/iap/purchase/verify with the legacy base64 receipt. The endpoint is
        // authorized, so attach the Bearer access token from AuthService.
        var body = new
        {
            platform = "apple",
            productId = purchase.ProductId,
            signedTransaction = purchase.SignedTransaction,
            receiptFormat = "legacy",
        };
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/iap/purchase/verify")
        {
            Content = JsonContent.Create(body),
        };
        var token = _billingAuthService!.AccessToken;
        if (!string.IsNullOrEmpty(token))
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var response = await _gatewayHttpClient!.SendAsync(request, CancellationToken.None);
        var responseBody = await response.Content.ReadAsStringAsync(CancellationToken.None);

        if (!response.IsSuccessStatusCode)
        {
            var message = ExtractVerifyError(responseBody) ?? $"Verify failed ({(int)response.StatusCode})";
            return new { success = false, errorCode = "verify_failed", message };
        }

        using var doc = JsonDocument.Parse(responseBody);
        var root = doc.RootElement;
        var isActive = root.TryGetProperty("isActive", out var ia) && ia.GetBoolean();
        var expiresAtUtc = root.TryGetProperty("expiresAtUtc", out var exp) && exp.ValueKind == JsonValueKind.String
            ? exp.GetString()
            : null;
        var subscriptionId = root.TryGetProperty("subscriptionId", out var sid) && sid.ValueKind == JsonValueKind.String
            ? sid.GetString()
            : null;
        return new { success = true, isActive, expiresAtUtc, subscriptionId };
    }

    private static string? PlanCodeToAppleProductId(string planCode) => planCode switch
    {
        "pro_month" => "corterm.pro.month",
        "pro_year" => "corterm.pro.year",
        "pro_lifetime" => "corterm.pro.lifetime",
        _ => null,
    };

    private static string? ExtractVerifyError(string responseBody)
    {
        try
        {
            using var doc = JsonDocument.Parse(responseBody);
            return doc.RootElement.TryGetProperty("message", out var m) ? m.GetString() : null;
        }
        catch
        {
            return null;
        }
    }
}
