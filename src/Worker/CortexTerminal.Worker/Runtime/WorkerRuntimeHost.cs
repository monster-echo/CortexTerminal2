using System.Collections.Concurrent;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Worker.Metrics;
using CortexTerminal.Worker.Pty;
using CortexTerminal.Worker.Registration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Runtime;

public sealed class WorkerRuntimeHost : IHostedService, IAsyncDisposable
{
    private readonly string _workerId;
    private readonly IWorkerGatewayClient _gatewayClient;
    private readonly IPtyHost _ptyHost;
    private readonly ILogger<WorkerRuntimeHost> _logger;
    private readonly ILoggerFactory _loggerFactory;
    private readonly IHostApplicationLifetime _lifetime;
    private readonly LinuxSystemMetricsCollector? _metricsCollector;
    private readonly TimeSpan _metricsInterval;
    private readonly ConcurrentDictionary<string, WorkerSessionRuntime> _sessions = [];
    private readonly List<IDisposable> _subscriptions = [];
    private readonly TimeSpan _reconnectInterval;
    private CancellationTokenSource? _reconnectCts;
    private CancellationTokenSource? _metricsCts;

    private static readonly TimeSpan DefaultReconnectInterval = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan DefaultMetricsInterval = TimeSpan.FromSeconds(5);

    public WorkerRuntimeHost(
        string workerId,
        IWorkerGatewayClient gatewayClient,
        IPtyHost ptyHost,
        ILoggerFactory loggerFactory,
        IHostApplicationLifetime lifetime,
        LinuxSystemMetricsCollector? metricsCollector = null,
        TimeSpan? metricsInterval = null)
        : this(workerId, gatewayClient, ptyHost, loggerFactory, lifetime, DefaultReconnectInterval, metricsCollector, metricsInterval) { }

    internal WorkerRuntimeHost(
        string workerId,
        IWorkerGatewayClient gatewayClient,
        IPtyHost ptyHost,
        ILoggerFactory loggerFactory,
        IHostApplicationLifetime lifetime,
        TimeSpan reconnectInterval,
        LinuxSystemMetricsCollector? metricsCollector = null,
        TimeSpan? metricsInterval = null)
    {
        _workerId = workerId;
        _gatewayClient = gatewayClient;
        _ptyHost = ptyHost;
        _loggerFactory = loggerFactory;
        _lifetime = lifetime;
        _logger = loggerFactory.CreateLogger<WorkerRuntimeHost>();
        _reconnectInterval = reconnectInterval;
        _metricsCollector = metricsCollector;
        _metricsInterval = metricsInterval ?? DefaultMetricsInterval;
    }

    public int ActiveSessionCount => _sessions.Count;

    public IReadOnlyList<TerminalChunk>? GetSessionScrollback(string sessionId)
        => _sessions.TryGetValue(sessionId, out var runtime) ? runtime.GetScrollback() : null;

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        _subscriptions.Add(_gatewayClient.OnStartSession(HandleStartSessionAsync));
        _subscriptions.Add(_gatewayClient.OnWriteInput(HandleWriteInputAsync));
        _subscriptions.Add(_gatewayClient.OnLatencyProbe(HandleLatencyProbeAsync));
        _subscriptions.Add(_gatewayClient.OnResizeSession(HandleResizeSessionAsync));
        _subscriptions.Add(_gatewayClient.OnCloseSession(HandleCloseSessionAsync));
        _subscriptions.Add(_gatewayClient.OnUpgradeWorker(HandleUpgradeWorkerAsync));
        _subscriptions.Add(_gatewayClient.OnRequestScrollback(HandleRequestScrollbackAsync));
        _subscriptions.Add(_gatewayClient.OnReconnected(connectionId =>
        {
            _logger.LogInformation("Worker {WorkerId} reconnected to gateway, connection={ConnectionId}.", _workerId, connectionId);
            return RegisterWorkerAsync(CancellationToken.None);
        }));
        _subscriptions.Add(_gatewayClient.OnClosed(ex =>
        {
            _logger.LogWarning(ex, "Worker {WorkerId} connection closed.", _workerId);
            _ = ReconnectLoopAsync();
            return Task.CompletedTask;
        }));

        _logger.LogInformation("Worker {WorkerId} is starting.", _workerId);
        try
        {
            await _gatewayClient.StartAsync(cancellationToken);
            await RegisterWorkerAsync(cancellationToken);
            StartMetricsLoop();
            Console.WriteLine("  Connected. Press Ctrl+C to stop.");
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            if (IsUnauthorized(ex))
            {
                _logger.LogCritical(ex, "Worker {WorkerId} rejected by gateway during initial connect (401). Re-login required. Stopping worker.", _workerId);
                _lifetime.StopApplication();
                return;
            }
            _logger.LogWarning("Worker {WorkerId} initial connection failed ({Error}), entering reconnect loop.", _workerId, ex.Message);
            _ = ReconnectLoopAsync();
        }
    }

    private void StartMetricsLoop()
    {
        if (_metricsCollector is null) return;
        _metricsCts?.Cancel();
        _metricsCts?.Dispose();
        _metricsCts = new CancellationTokenSource();
        _ = MetricsLoopAsync(_metricsCts.Token);
    }

    private async Task MetricsLoopAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Starting metrics loop for worker {WorkerId}, interval={Interval}s.", _workerId, _metricsInterval.TotalSeconds);
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(_metricsInterval, cancellationToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }

            try
            {
                var snapshot = await _metricsCollector!.SnapshotAsync(cancellationToken);
                if (snapshot is null) continue;
                var frame = BuildWorkerInfoFrame(snapshot);
                await _gatewayClient.SendWorkerInfoAsync(frame, cancellationToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to sample or report metrics for worker {WorkerId}.", _workerId);
            }
        }
    }

    private WorkerInfoFrame BuildWorkerInfoFrame(WorkerMetricsSnapshot? snapshot)
    {
        return new WorkerInfoFrame(
            _workerId,
            Environment.MachineName,
            RuntimeInformation.OSDescription,
            RuntimeInformation.OSArchitecture.ToString(),
            Environment.MachineName,
            Assembly.GetEntryAssembly()?.GetName().Version?.ToString(3),
            snapshot?.CpuUsagePercent,
            snapshot?.MemoryUsagePercent);
    }

    private async Task ReconnectLoopAsync()
    {
        _reconnectCts?.Cancel();
        _reconnectCts?.Dispose();
        _reconnectCts = new CancellationTokenSource();
        var ct = _reconnectCts.Token;

        _logger.LogWarning("Worker {WorkerId} connection lost. Reconnecting every {Interval}s...", _workerId, _reconnectInterval.TotalSeconds);

        while (!ct.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(_reconnectInterval, ct);
            }
            catch (OperationCanceledException)
            {
                return;
            }

            try
            {
                await _gatewayClient.StartAsync(ct);
                await RegisterWorkerAsync(ct);
                _logger.LogInformation("Worker {WorkerId} reconnected successfully.", _workerId);
                return;
            }
            catch (Exception ex) when (IsUnauthorized(ex))
            {
                _logger.LogCritical(ex, "Worker {WorkerId} rejected by gateway during reconnect (401). Re-login required. Stopping worker.", _workerId);
                _lifetime.StopApplication();
                return;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogWarning(ex, "Worker {WorkerId} reconnect failed, retrying...", _workerId);
            }
        }
    }

    private static bool IsUnauthorized(Exception ex)
    {
        for (var e = ex; e is not null; e = e.InnerException)
        {
            if (e is HttpRequestException hre && hre.StatusCode == System.Net.HttpStatusCode.Unauthorized)
                return true;
        }
        return false;
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Worker {WorkerId} is stopping.", _workerId);
        _reconnectCts?.Cancel();
        _metricsCts?.Cancel();
        foreach (var subscription in _subscriptions)
        {
            subscription.Dispose();
        }

        _subscriptions.Clear();

        _logger.LogInformation("Closing {SessionCount} active sessions for worker {WorkerId}.", _sessions.Count, _workerId);
        foreach (var session in _sessions.ToArray())
        {
            if (_sessions.TryRemove(session.Key, out var runtime))
            {
                await runtime.CloseAsync(cancellationToken);
                await runtime.DisposeAsync();
            }
        }
        _logger.LogInformation("Worker {WorkerId} has stopped.", _workerId);
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync(CancellationToken.None);
        await _gatewayClient.DisposeAsync();
        _logger.LogDebug("Worker {WorkerId} has been disposed.", _workerId);
    }

    private async Task RegisterWorkerAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Registering worker {WorkerId}.", _workerId);
        await _gatewayClient.RegisterAsync(_workerId, cancellationToken);

        WorkerMetricsSnapshot? snapshot = null;
        if (_metricsCollector is not null)
        {
            try
            {
                snapshot = await _metricsCollector.SnapshotAsync(cancellationToken);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to capture initial metrics for {WorkerId}.", _workerId);
            }
        }

        var info = BuildWorkerInfoFrame(snapshot);

        try
        {
            await _gatewayClient.SendWorkerInfoAsync(info, cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to send worker info for {WorkerId}.", _workerId);
        }
    }

    private async Task HandleStartSessionAsync(StartSessionCommand command)
    {
        if (_sessions.ContainsKey(command.SessionId))
        {
            await _gatewayClient.ForwardStartFailedAsync(
                new SessionStartFailedEvent(command.SessionId, "duplicate-session"),
                CancellationToken.None);
            _logger.LogWarning("Received start command for duplicate session {SessionId}.", command.SessionId);
            return;
        }

        var runtime = new WorkerSessionRuntime(
            command.SessionId,
            _ptyHost,
            _gatewayClient,
            _loggerFactory.CreateLogger<WorkerSessionRuntime>(),
            command.MaxBytes);


        runtime.Terminated += RemoveSessionAsync;

        if (!_sessions.TryAdd(command.SessionId, runtime))
        {
            await runtime.CloseAsync(CancellationToken.None);
            await runtime.DisposeAsync();
            await _gatewayClient.ForwardStartFailedAsync(
                new SessionStartFailedEvent(command.SessionId, "duplicate-session"),
                CancellationToken.None);
            return;
        }

        try
        {
            _logger.LogInformation("Starting session {SessionId}.", command.SessionId);
            await runtime.StartAsync(command.Columns, command.Rows, CancellationToken.None);
        }
        catch (Exception exception)
        {
            _sessions.TryRemove(command.SessionId, out _);
            await runtime.CloseAsync(CancellationToken.None);
            await runtime.DisposeAsync();
            _logger.LogError(exception, "Failed to start session {SessionId}.", command.SessionId);
            var reason = exception is PtySupportException ptySupportException
                ? ptySupportException.ErrorCode
                : exception.Message;
            await _gatewayClient.ForwardStartFailedAsync(
                new SessionStartFailedEvent(command.SessionId, reason),
                CancellationToken.None);
        }
    }

    private Task HandleWriteInputAsync(WriteInputFrame frame)
    {
        _logger.LogDebug("Received input for session {SessionId}, {ByteCount} bytes.", frame.SessionId, frame.Payload.Length);

        return _sessions.TryGetValue(frame.SessionId, out var runtime)
        ? runtime.WriteInputAsync(frame.Payload, CancellationToken.None)
        : LogMissingSessionAsync(frame.SessionId, "write");
    }

    private Task HandleLatencyProbeAsync(LatencyProbeFrame frame)
    {
        _logger.LogDebug("Received latency probe for session {SessionId}: {ProbeId}", frame.SessionId, frame.ProbeId);

        return _sessions.ContainsKey(frame.SessionId)
            ? _gatewayClient.ForwardLatencyProbeAsync(frame, CancellationToken.None)
            : LogMissingSessionAsync(frame.SessionId, "latency-probe");
    }

    private Task HandleResizeSessionAsync(ResizePtyRequest request)
    {
        _logger.LogDebug("Received resize for session {SessionId}: {Columns}x{Rows}", request.SessionId, request.Columns, request.Rows);
        if (!TerminalSizeLimits.IsValid(request.Columns, request.Rows))
        {
            _logger.LogWarning("Ignoring invalid resize for session {SessionId}: {Columns}x{Rows}", request.SessionId, request.Columns, request.Rows);
            return Task.CompletedTask;
        }

        return _sessions.TryGetValue(request.SessionId, out var runtime)
        ? runtime.ResizeAsync(request.Columns, request.Rows, CancellationToken.None)
        : LogMissingSessionAsync(request.SessionId, "resize");
    }

    private async Task HandleCloseSessionAsync(CloseSessionRequest request)
    {
        _logger.LogDebug("Received close for session {SessionId}", request.SessionId);
        if (_sessions.TryRemove(request.SessionId, out var runtime))
        {
            await runtime.CloseAsync(CancellationToken.None);
            await runtime.DisposeAsync();
            return;
        }

        await LogMissingSessionAsync(request.SessionId, "close");
    }

    private async Task RemoveSessionAsync(string sessionId)
    {
        _logger.LogDebug("Removing session {SessionId}", sessionId);

        if (_sessions.TryRemove(sessionId, out var runtime))
        {
            await runtime.DisposeAsync();
        }
    }

    private Task LogMissingSessionAsync(string sessionId, string operation)
    {
        _logger.LogDebug("Ignoring {Operation} for unknown session {SessionId}.", operation, sessionId);
        return Task.CompletedTask;
    }

    private IReadOnlyList<TerminalChunk> HandleRequestScrollbackAsync(string sessionId)
    {
        var scrollback = GetSessionScrollback(sessionId);
        if (scrollback is null)
        {
            _logger.LogWarning("RequestScrollback for unknown session {SessionId}, returning empty.", sessionId);
            return Array.Empty<TerminalChunk>();
        }
        _logger.LogInformation("RequestScrollback for session {SessionId}, returning {ChunkCount} chunks.", sessionId, scrollback.Count);
        return scrollback;
    }

    private static readonly SemaphoreSlim _upgradeLock = new(1, 1);

    internal static bool DoesDownloadUrlMatchLocalPlatform(string downloadUrl)
    {
        var fileName = downloadUrl.Split('/').LastOrDefault() ?? "";
        var match = Regex.Match(fileName, @"corterm-(\w+)-(\w+)\.(tar\.gz|zip)", RegexOptions.IgnoreCase);
        if (!match.Success) return true;

        var urlOs = match.Groups[1].Value;
        var urlArch = match.Groups[2].Value;

        var localOs = RuntimeInformation.IsOSPlatform(OSPlatform.OSX) ? "osx"
            : RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? "win"
            : "linux";
        var localArch = RuntimeInformation.ProcessArchitecture == Architecture.Arm64 ? "arm64" : "x64";

        return string.Equals(urlOs, localOs, StringComparison.OrdinalIgnoreCase)
            && string.Equals(urlArch, localArch, StringComparison.OrdinalIgnoreCase);
    }

    private async Task HandleUpgradeWorkerAsync(UpgradeWorkerCommand command)
    {
        if (!_upgradeLock.Wait(0))
        {
            _logger.LogWarning("Upgrade already in progress, ignoring duplicate command.");
            return;
        }

        _logger.LogInformation("Received upgrade command: target={TargetVersion}, url={DownloadUrl}", command.TargetVersion, command.DownloadUrl);

        if (!DoesDownloadUrlMatchLocalPlatform(command.DownloadUrl))
        {
            _logger.LogError(
                "Upgrade rejected: download URL platform does not match local platform. Local: {LocalOS}/{LocalArch}, URL: {DownloadUrl}.",
                RuntimeInformation.OSDescription,
                RuntimeInformation.ProcessArchitecture,
                command.DownloadUrl);
            return;
        }

        try
        {
            var isWindows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);
            string tmpFile;

            // Download
            using (var http = new HttpClient())
            {
                var tmpDir = Path.Combine(Path.GetTempPath(), $"corterm-upgrade-{Guid.NewGuid():N}");
                Directory.CreateDirectory(tmpDir);
                tmpFile = Path.Combine(tmpDir, isWindows ? "corterm.zip" : "corterm.tar.gz");

                _logger.LogInformation("Downloading upgrade from {Url} ...", command.DownloadUrl);
                var data = await http.GetByteArrayAsync(command.DownloadUrl);
                await File.WriteAllBytesAsync(tmpFile, data);
                _logger.LogInformation("Download complete ({Size} bytes), extracting ...", data.Length);

                // Extract to temp directory
                var extractDir = Path.Combine(tmpDir, "extracted");
                Directory.CreateDirectory(extractDir);

                if (isWindows)
                {
                    System.IO.Compression.ZipFile.ExtractToDirectory(tmpFile, extractDir, overwriteFiles: true);
                }
                else
                {
                    var tar = Process.Start(new ProcessStartInfo("tar", $"-xzf \"{tmpFile}\" -C \"{extractDir}\"")
                    {
                        UseShellExecute = false
                    });
                    if (tar is not null)
                    {
                        await tar.WaitForExitAsync();
                    }
                }

                // Replace binary
                var newBinary = Path.Combine(extractDir, isWindows ? "corterm.exe" : "corterm");
                if (!File.Exists(newBinary))
                {
                    _logger.LogError("Upgrade failed: binary not found in archive at {Path}", newBinary);
                    return;
                }

                var currentBinary = Process.GetCurrentProcess().MainModule?.FileName
                    ?? throw new InvalidOperationException("Cannot determine current process path.");

                // Write new binary to .new file first, then atomic replace.
                // This ensures the current binary remains intact if the copy fails.
                var stagingPath = currentBinary + ".new";
                File.Copy(newBinary, stagingPath, overwrite: true);
                if (!isWindows)
                {
                    try { File.SetUnixFileMode(stagingPath, UnixFileMode.UserExecute | UnixFileMode.GroupExecute | UnixFileMode.OtherRead | UnixFileMode.UserRead | UnixFileMode.GroupRead); } catch { }
                }
                File.Move(stagingPath, currentBinary, overwrite: true);

                _logger.LogInformation("Binary replaced. Restarting via OS service manager ...");

                RestartViaServiceManager();
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Upgrade failed.");
        }
    }

    private static void RestartViaServiceManager()
    {
        var isWindows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);
        var isOsx = RuntimeInformation.IsOSPlatform(OSPlatform.OSX);

        string program, args;
        if (isWindows)
        {
            program = "cmd";
            args = "/c \"taskkill /IM corterm.exe /F & schtasks /run /tn \\\"Corterm Worker\\\"\"";
        }
        else if (isOsx)
        {
            var homeDir = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            var plistPath = Path.Combine(homeDir, "Library/LaunchAgents/com.corterm.worker.plist");
            program = "bash";
            args = $"-c \"launchctl unload '{plistPath}' && launchctl load '{plistPath}'\"";
        }
        else
        {
            program = "systemctl";
            args = "--user restart corterm-worker";
        }

        Process.Start(new ProcessStartInfo(program, args)
        {
            UseShellExecute = false,
            CreateNoWindow = true
        });

        Environment.Exit(0);
    }
}
