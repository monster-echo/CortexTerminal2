using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Http;

namespace CortexTerminal.Gateway.Audit;

public static class AuditRequestExtensions
{
    private static readonly Regex MobileAppParenthesizedRegex =
        new(@"\(([^)]+)\)\s*$", RegexOptions.Compiled);

    private static readonly Regex AndroidModelRegex =
        new(@"Android\s+[\d.]+;\s*([^);]+?)(?:\s+Build/|\))", RegexOptions.Compiled, TimeSpan.FromSeconds(1));

    /// <summary>
    /// Build an AuditLogEntry populated with the request's IP, User-Agent, and a best-effort
    /// device-model parse. Use this at HTTP call sites (controllers, minimal APIs).
    /// Hub call sites without an HttpContext should keep using the bare constructor.
    /// </summary>
    public static AuditLogEntry CreateAuditEntry(
        this HttpContext httpContext,
        string userId,
        string userName,
        string action,
        string targetEntity,
        string targetId,
        string? id = null,
        DateTimeOffset? timestamp = null)
    {
        var ip = httpContext.Connection.RemoteIpAddress?.ToString();
        var ua = httpContext.Request.Headers.UserAgent.ToString();
        var device = ParseDeviceModel(ua);
        return new AuditLogEntry(
            id ?? Guid.NewGuid().ToString("N"),
            timestamp ?? DateTimeOffset.UtcNow,
            userId,
            userName,
            action,
            targetEntity,
            targetId,
            string.IsNullOrEmpty(ip) ? null : ip,
            string.IsNullOrEmpty(ua) ? null : ua,
            device);
    }

    public static string? ParseDeviceModel(string? userAgent)
    {
        if (string.IsNullOrWhiteSpace(userAgent)) return null;

        // Our own client UA: CortexTerminal.Mobile.App/{ver} ({platform}; {model}; {osVersion})
        var ma = MobileAppParenthesizedRegex.Match(userAgent);
        if (ma.Success)
        {
            var parts = ma.Groups[1].Value.Split(';');
            if (parts.Length >= 2)
            {
                var platform = parts[0].Trim();
                var model = parts[1].Trim();
                if (!string.IsNullOrWhiteSpace(model)) return $"{platform}/{model}";
            }
        }

        // Legacy iOS (CFNetwork / Darwin) before we set explicit UA
        if (userAgent.Contains("CFNetwork", StringComparison.OrdinalIgnoreCase) ||
            userAgent.Contains("Darwin", StringComparison.OrdinalIgnoreCase))
        {
            return "iOS";
        }

        // Legacy Android Dalvik UA: ...Android 16; SM-S9280 Build/...
        var android = AndroidModelRegex.Match(userAgent);
        if (android.Success) return $"Android/{android.Groups[1].Value.Trim()}";

        // Browsers / curl / etc
        if (userAgent.Contains("Mozilla", StringComparison.OrdinalIgnoreCase) ||
            userAgent.Contains("Chrome", StringComparison.OrdinalIgnoreCase) ||
            userAgent.Contains("Safari", StringComparison.OrdinalIgnoreCase) ||
            userAgent.Contains("Firefox", StringComparison.OrdinalIgnoreCase) ||
            userAgent.Contains("curl", StringComparison.OrdinalIgnoreCase) ||
            userAgent.Contains("libcurl", StringComparison.OrdinalIgnoreCase))
        {
            return "Browser";
        }

        return null;
    }
}
