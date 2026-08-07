using System.Text.Json.Nodes;

namespace CortexTerminal.Worker;

/// <summary>
/// Trim-safe JSON builders for <c>corterm --json</c> output.
///
/// The worker binary is published with <c>PublishTrimmed=true</c>, where reflection-based
/// <c>JsonSerializer.Serialize&lt;T&gt;</c> on unregistered types silently throws and gets
/// swallowed (see the DecodeJwtPayload comment). Building JsonObject/JsonArray DOM trees and
/// calling <c>ToJsonString()</c> is reflection-free and trims safely — the same pattern the
/// AgentEventEndpoint and ClaudeCodeAdapter already use.
/// </summary>
internal static class CliJson
{
    public static JsonObject Status(
        string version, int pid, string uptime, string gateway, string workerId,
        bool authenticated, string? user, string? authExpiry,
        JsonObject? gatewayInfo, bool updateAvailable, JsonArray workers)
    {
        return new JsonObject
        {
            ["version"] = version,
            ["pid"] = pid,
            ["uptime"] = uptime,
            ["gateway"] = gateway,
            ["workerId"] = workerId,
            ["authenticated"] = authenticated,
            ["user"] = user,
            ["authExpiry"] = authExpiry,
            ["gatewayInfo"] = gatewayInfo,
            ["updateAvailable"] = updateAvailable,
            ["workers"] = workers,
        };
    }

    public static JsonObject Worker(
        string workerId, string? name, string? hostname, string? operatingSystem, string? architecture,
        string? version, bool isOnline, string? lastSeenAtUtc, int? sessionCount,
        double? cpuUsagePercent, double? memoryUsagePercent)
    {
        return new JsonObject
        {
            ["workerId"] = workerId,
            ["name"] = name,
            ["hostname"] = hostname,
            ["operatingSystem"] = operatingSystem,
            ["architecture"] = architecture,
            ["version"] = version,
            ["isOnline"] = isOnline,
            ["lastSeenAtUtc"] = lastSeenAtUtc,
            ["sessionCount"] = sessionCount,
            ["cpuUsagePercent"] = cpuUsagePercent,
            ["memoryUsagePercent"] = memoryUsagePercent,
        };
    }

    public static JsonObject Doctor(IReadOnlyList<(string Name, bool Ok, string Detail)> checks)
    {
        var arr = new JsonArray();
        foreach (var (name, ok, detail) in checks)
        {
            // Cast to JsonNode so the non-generic Add(JsonNode) overload is used; the generic
            // Add<T>(T) boxes the object into a JsonValue, which serializes inconsistently
            // under partial trimming.
            arr.Add((JsonNode)new JsonObject
            {
                ["name"] = name,
                ["ok"] = ok,
                ["detail"] = detail,
            });
        }
        return new JsonObject
        {
            ["checks"] = arr,
            ["passedCount"] = checks.Count(c => c.Ok),
            ["failedCount"] = checks.Count(c => !c.Ok),
        };
    }

    public static JsonObject UpdateCheck(string currentVersion, string? latestVersion, bool updateAvailable, string? assetName, string? downloadUrl)
    {
        return new JsonObject
        {
            ["currentVersion"] = currentVersion,
            ["latestVersion"] = latestVersion,
            ["updateAvailable"] = updateAvailable,
            ["assetName"] = assetName,
            ["downloadUrl"] = downloadUrl,
        };
    }

    public static JsonObject Service(string action, bool ok, string message, string? error = null)
    {
        return new JsonObject
        {
            ["action"] = action,
            ["ok"] = ok,
            ["message"] = message,
            ["error"] = error,
        };
    }

    public static JsonObject Logout(bool ok, string message)
    {
        return new JsonObject
        {
            ["ok"] = ok,
            ["message"] = message,
        };
    }

    public static JsonObject LoginStage(string stage, string? verificationUri = null, string? userCode = null,
        int? expiresInSeconds = null, int? pollIntervalSeconds = null, string? message = null)
    {
        return new JsonObject
        {
            ["stage"] = stage,
            ["verificationUri"] = verificationUri,
            ["userCode"] = userCode,
            ["expiresInSeconds"] = expiresInSeconds,
            ["pollIntervalSeconds"] = pollIntervalSeconds,
            ["message"] = message,
        };
    }

    public static JsonObject UpdateStage(string stage, string? version = null, long? bytes = null, string? message = null)
    {
        return new JsonObject
        {
            ["stage"] = stage,
            ["version"] = version,
            ["bytes"] = bytes,
            ["message"] = message,
        };
    }
}
