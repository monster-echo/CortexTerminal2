using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Threading;
using CommunityToolkit.Maui.Core;
using CortexTerminal.Mobile.Core.Bridge;
using CortexTerminal.Mobile.Core.Configuration;
using CortexTerminal.Mobile.Core.Diagnostics;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Mobile.App.Services.Bridge;

public sealed partial class AppBridge(ILogger<AppBridge> logger) : IBridgeContract
{
    public const string PendingNavigationRouteKey = "template.pending_navigation.route";
    public const string PendingNavigationPayloadKey = "template.pending_navigation.payload";
    public const string WebFileRoutePrefix = "/__backend-file/";
    private const int MaxRecentOperations = 20;

    private readonly AppSettings _appSettings = new(
        GatewayBaseUri: "https://gateway.ct.rwecho.top",
        SupportEmail: "support@example.com",
        PrivacyPolicyUrl: "https://example.com/privacy",
        TermsOfServiceUrl: "https://example.com/terms",
        EnableDiagnostics: true,
        EnableFeatureShowcase: true);
    private readonly ConcurrentQueue<BridgeOperationInfo> _recentOperations = new();
    private readonly ConcurrentDictionary<string, RegisteredWebFile> _registeredWebFiles = new();
    private readonly object _binaryStreamSyncRoot = new();
    private IToast? _activeToast;
    private ISnackbar? _activeSnackbar;
    private Func<string, string, Task>? _sendRawMessageToWebViewAsync;
    private CancellationTokenSource? _binaryStreamCts;
    private int _totalCalls;
    private int _failureCount;

    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false,
    };

    public void ConfigureWebViewMessaging(Func<string, string, Task> sendRawMessageToWebViewAsync)
    {
        _sendRawMessageToWebViewAsync = sendRawMessageToWebViewAsync;
    }

    public string RegisterWebFile(string filePath, string? contentType = null, string? fileName = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);

        var token = Guid.NewGuid().ToString("N");
        var resolvedFileName = string.IsNullOrWhiteSpace(fileName)
            ? Path.GetFileName(filePath)
            : fileName;

        _registeredWebFiles[token] = new RegisteredWebFile(
            filePath,
            string.IsNullOrWhiteSpace(contentType) ? GuessContentType(filePath) : contentType,
            resolvedFileName,
            DateTimeOffset.UtcNow);

        return $"{WebFileRoutePrefix}{token}/{Uri.EscapeDataString(resolvedFileName)}";
    }

    public bool TryResolveWebFile(Uri? uri, out RegisteredWebFile? file)
    {
        file = null;
        if (uri is null)
        {
            return false;
        }

        var absolutePath = uri.AbsolutePath;
        if (!absolutePath.StartsWith(WebFileRoutePrefix, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var tokenAndName = absolutePath[WebFileRoutePrefix.Length..];
        if (string.IsNullOrWhiteSpace(tokenAndName))
        {
            return false;
        }

        var slashIndex = tokenAndName.IndexOf('/');
        var token = slashIndex >= 0 ? tokenAndName[..slashIndex] : tokenAndName;
        return _registeredWebFiles.TryGetValue(token, out file);
    }

    internal static string GuessContentType(string? fileName)
    {
        var extension = Path.GetExtension(fileName)?.ToLowerInvariant();
        return extension switch
        {
            ".png" => "image/png",
            ".gif" => "image/gif",
            ".webp" => "image/webp",
            ".heic" or ".heif" => "image/heic",
            ".svg" => "image/svg+xml",
            ".mp4" => "video/mp4",
            ".mov" => "video/quicktime",
            ".m4v" => "video/x-m4v",
            ".webm" => "video/webm",
            _ => "image/jpeg",
        };
    }

    internal static string GuessExtension(string contentType)
    {
        return contentType.ToLowerInvariant() switch
        {
            "image/png" => ".png",
            "image/gif" => ".gif",
            "image/webp" => ".webp",
            "image/heic" => ".heic",
            "image/svg+xml" => ".svg",
            "video/mp4" => ".mp4",
            "video/quicktime" => ".mov",
            "video/x-m4v" => ".m4v",
            "video/webm" => ".webm",
            _ => ".jpg",
        };
    }

    private Task SendEventToWebViewAsync(object payload, string reason)
    {
        if (_sendRawMessageToWebViewAsync is null)
        {
            throw new InvalidOperationException("HybridWebView messaging is not configured.");
        }

        return _sendRawMessageToWebViewAsync(JsonSerializer.Serialize(payload, _jsonOptions), reason);
    }

    private async Task<string> ExecuteSafeAsync<T>(Func<Task<T>> operation, [System.Runtime.CompilerServices.CallerMemberName] string operationName = "")
    {
        var stopwatch = Stopwatch.StartNew();
        try
        {
            LogDiag($"[BRIDGE] {operationName} ENTER thread={Environment.CurrentManagedThreadId}");
            var result = await operation();
            RecordOperation(operationName, stopwatch.ElapsedMilliseconds, true);
            LogDiag($"[BRIDGE] {operationName} DONE in {stopwatch.ElapsedMilliseconds}ms");
            return JsonSerializer.Serialize(result, _jsonOptions);
        }
        catch (Exception ex)
        {
            LogDiag($"[BRIDGE] {operationName} FAIL in {stopwatch.ElapsedMilliseconds}ms: {ex.Message}");
            RecordOperation(operationName, stopwatch.ElapsedMilliseconds, false, ex.Message);
            return JsonSerializer.Serialize(new { error = ex.Message }, _jsonOptions);
        }
    }

    private async Task<string> ExecuteSafeVoidAsync(Func<Task> operation, [System.Runtime.CompilerServices.CallerMemberName] string operationName = "")
    {
        var stopwatch = Stopwatch.StartNew();
        try
        {
            LogDiag($"[BRIDGE] {operationName} ENTER thread={Environment.CurrentManagedThreadId}");
            await operation();
            RecordOperation(operationName, stopwatch.ElapsedMilliseconds, true);
            LogDiag($"[BRIDGE] {operationName} DONE in {stopwatch.ElapsedMilliseconds}ms");
            return JsonSerializer.Serialize(new { success = true }, _jsonOptions);
        }
        catch (Exception ex)
        {
            LogDiag($"[BRIDGE] {operationName} FAIL in {stopwatch.ElapsedMilliseconds}ms: {ex.Message}");
            RecordOperation(operationName, stopwatch.ElapsedMilliseconds, false, ex.Message);
            return JsonSerializer.Serialize(new { error = ex.Message }, _jsonOptions);
        }
    }

    private void RecordOperation(string operationName, long durationMs, bool isSuccess, string? errorMessage = null)
    {
        Interlocked.Increment(ref _totalCalls);
        if (!isSuccess)
        {
            Interlocked.Increment(ref _failureCount);
        }

        _recentOperations.Enqueue(new BridgeOperationInfo(
            operationName,
            durationMs,
            isSuccess,
            DateTimeOffset.UtcNow,
            errorMessage));

        while (_recentOperations.Count > MaxRecentOperations && _recentOperations.TryDequeue(out _))
        {
        }
    }

    public sealed record RegisteredWebFile(
        string FilePath,
        string ContentType,
        string FileName,
        DateTimeOffset RegisteredAt);

    private static void LogDiag(string message)
    {
#if ANDROID
        Android.Util.Log.Info("CT", message);
#else
        System.Diagnostics.Debug.WriteLine(message);
#endif
    }
}
