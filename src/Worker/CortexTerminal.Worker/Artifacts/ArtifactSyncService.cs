using System.Collections.Concurrent;
using System.Text.RegularExpressions;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Registration;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Artifacts;

/// <summary>
/// Watches the session's local artifacts directory and uploads files the user/agent creates to S3
/// by requesting presigned PUT URLs from the Gateway. Never holds S3 credentials — all uploads
/// go through HttpClient against URLs brokered by the Gateway.
///
/// Pipeline per file change: FS watcher event → debounce → stability check → size cap → SHA256
/// dedup → request upload URL → HttpClient PUT → report completion. Created/started per session,
/// disposed when the session terminates.
/// </summary>
public sealed class ArtifactSyncService : IAsyncDisposable
{
    private static readonly Regex TempFilePattern = new(@"(^\.|~$|\.tmp$|\.swp$|\.bak$|\.DS_Store$)",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static readonly TimeSpan DebounceInterval = TimeSpan.FromSeconds(1);
    private static readonly TimeSpan StabilityTimeout = TimeSpan.FromSeconds(5);

    private readonly string _sessionId;
    private readonly string _artifactsDir;
    private readonly IWorkerGatewayClient _gateway;
    private readonly HttpClient _httpClient;
    private readonly ILogger<ArtifactSyncService> _logger;
    private readonly FileSystemWatcher? _watcher;
    private readonly CancellationTokenSource _cts = new();
    private readonly ConcurrentDictionary<string, Task> _pending = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, string> _lastUploadedHash = new(StringComparer.Ordinal);
    private readonly long _maxSizeBytes = 50 * 1024 * 1024;
    private int _disposed;

    public ArtifactSyncService(
        string sessionId,
        string artifactsDir,
        IWorkerGatewayClient gateway,
        HttpClient httpClient,
        long maxSizeBytes,
        ILogger<ArtifactSyncService> logger)
    {
        _sessionId = sessionId;
        _artifactsDir = artifactsDir;
        _gateway = gateway;
        _httpClient = httpClient;
        _maxSizeBytes = maxSizeBytes;
        _logger = logger;

        if (!OperatingSystem.IsBrowser())
        {
            _watcher = new FileSystemWatcher(artifactsDir)
            {
                IncludeSubdirectories = false,
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size,
                EnableRaisingEvents = true
            };
            _watcher.Created += (_, e) => OnFileChanged(e.FullPath);
            _watcher.Changed += (_, e) => OnFileChanged(e.FullPath);
            _watcher.Deleted += (_, e) => OnFileDeleted(e.FullPath);
        }
    }

    public Task StartAsync(CancellationToken ct)
    {
        if (_watcher is null) return Task.CompletedTask;

        foreach (var path in Directory.EnumerateFiles(_artifactsDir))
        {
            OnFileChanged(path);
        }
        return Task.CompletedTask;
    }

    private void OnFileChanged(string fullPath)
    {
        var filename = Path.GetFileName(fullPath);
        if (TempFilePattern.IsMatch(filename)) return;
        if (!ArtifactFilenameValidator.IsValid(filename)) return;

        var dedupKey = $"{_sessionId}:{filename}";
        _pending[dedupKey] = Task.Run(() => UploadAfterDebounceAsync(fullPath, filename, _cts.Token));
    }

    private void OnFileDeleted(string fullPath)
    {
        var filename = Path.GetFileName(fullPath);
        if (!ArtifactFilenameValidator.IsValid(filename)) return;

        var dedupKey = $"{_sessionId}:{filename}";
        _lastUploadedHash.TryRemove(dedupKey, out _);
        _ = _gateway.ReportArtifactDeletedAsync(
            new ReportArtifactDeletedFrame(_sessionId, filename),
            _cts.Token);
    }

    private async Task UploadAfterDebounceAsync(string fullPath, string filename, CancellationToken ct)
    {
        try
        {
            await Task.Delay(DebounceInterval, ct);
            if (!await WaitForStableAsync(fullPath, ct)) return;

            long size;
            try { size = new FileInfo(fullPath).Length; }
            catch (FileNotFoundException) { return; }
            catch (IOException) { return; }

            if (size <= 0 || size > _maxSizeBytes)
            {
                _logger.LogWarning("ArtifactSync skip {Filename}: size {Size} outside [1, {Max}].",
                    filename, size, _maxSizeBytes);
                return;
            }

            var sha = await ArtifactMirror.ComputeSha256Async(fullPath, ct);
            var dedupKey = $"{_sessionId}:{filename}";
            if (_lastUploadedHash.TryGetValue(dedupKey, out var prev) && string.Equals(prev, sha, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            var resp = await _gateway.RequestArtifactUploadUrlAsync(
                new CreateArtifactRequest(_sessionId, filename, size, sha, ArtifactOrigin.Worker),
                ct);
            if (string.IsNullOrEmpty(resp.UploadUrl))
            {
                _logger.LogWarning("ArtifactSync got empty upload URL for {Filename}.", filename);
                return;
            }

            using (var stream = File.OpenRead(fullPath))
            using (var content = new StreamContent(stream))
            {
                using var putResp = await _httpClient.PutAsync(resp.UploadUrl, content, ct);
                putResp.EnsureSuccessStatusCode();
            }

            var ack = await _gateway.CompleteArtifactUploadAsync(
                new CompleteArtifactRequest(resp.ArtifactId, sha),
                ct);
            if (ack.Success)
            {
                _lastUploadedHash[dedupKey] = sha;
                _logger.LogInformation("ArtifactSync uploaded {Filename} (artifact {ArtifactId}, {Size} bytes).",
                    filename, resp.ArtifactId, size);
            }
            else
            {
                _logger.LogWarning("ArtifactSync upload rejected by gateway for {Filename}: {Error}.",
                    filename, ack.Error);
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "ArtifactSync failed for {Filename}.", filename);
        }
        finally
        {
            _pending.TryRemove($"{_sessionId}:{filename}", out _);
        }
    }

    private static async Task<bool> WaitForStableAsync(string path, CancellationToken ct)
    {
        var deadline = DateTimeOffset.UtcNow.Add(StabilityTimeout);
        long lastSize = -1;
        while (DateTimeOffset.UtcNow < deadline)
        {
            try
            {
                if (!File.Exists(path)) return false;
                var size = new FileInfo(path).Length;
                if (size == lastSize && size > 0) return true;
                lastSize = size;
            }
            catch (FileNotFoundException) { return false; }
            catch (IOException) { /* file locked, retry */ }

            await Task.Delay(DebounceInterval, ct);
        }
        return false;
    }

    public async ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref _disposed, 1) == 1) return;

        _cts.Cancel();
        if (_watcher is not null)
        {
            _watcher.EnableRaisingEvents = false;
            _watcher.Dispose();
        }

        try
        {
            await Task.WhenAll(_pending.Values.Where(t => !t.IsCompleted).DefaultIfEmpty(Task.CompletedTask));
        }
        catch (OperationCanceledException) { /* expected on shutdown */ }
        catch (Exception ex) { _logger.LogDebug(ex, "ArtifactSync awaiting pending uploads on dispose."); }

        _cts.Dispose();
    }
}
