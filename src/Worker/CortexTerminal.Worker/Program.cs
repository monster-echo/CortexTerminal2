using System.CommandLine;
using System.Diagnostics;
using System.Net.Http.Json;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using CortexTerminal.Worker.Auth;
using CortexTerminal.Worker.Pty;
using CortexTerminal.Worker.Registration;
using CortexTerminal.Worker.Runtime;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

var installDir = AppContext.BaseDirectory;
var version = Assembly.GetEntryAssembly()?.GetName().Version?.ToString() ?? "0.0.0";

// Prefer IPv4: many environments advertise IPv6 via DNS but lack actual connectivity,
// causing SocketsHttpHandler to hang on the first IPv6 attempt before falling back.
Environment.SetEnvironmentVariable("DOTNET_SYSTEM_NET_DISABLEIPV6", "1");

// ── Helper: resolve gateway URL ──
static string ResolveGatewayUrl(string installDir)
{
    var url = Environment.GetEnvironmentVariable("CORTERM_GATEWAY_URL");
    if (string.IsNullOrWhiteSpace(url))
    {
        url = Environment.GetEnvironmentVariable("CORTEX_GATEWAY_URL");
    }
    if (!string.IsNullOrWhiteSpace(url)) return url;

    var config = new ConfigurationBuilder()
        .SetBasePath(installDir)
        .AddJsonFile("appsettings.json", optional: true)
        .Build();
    url = config["Worker:GatewayUrl"];

    if (string.IsNullOrWhiteSpace(url))
    {
        Console.Error.WriteLine("Gateway URL is not configured.");
        Console.Error.WriteLine("  Set CORTERM_GATEWAY_URL environment variable or Worker:GatewayUrl in appsettings.json.");
        Environment.Exit(1);
        return ""; // unreachable
    }
    return url;
}

// ── Helper: resolve worker ID ──
static string ResolveWorkerId()
{
    return Environment.GetEnvironmentVariable("CORTERM_WORKER_ID")
        ?? Environment.GetEnvironmentVariable("CORTEX_WORKER_ID")
        ?? new ConfigurationBuilder()
            .AddEnvironmentVariables()
            .Build()["Worker:WorkerId"]
        ?? $"worker-{Environment.MachineName}".ToLowerInvariant();
}

// ── Helper: decode JWT payload ──
static Dictionary<string, JsonElement>? DecodeJwtPayload(string token)
{
    try
    {
        var parts = token.Split('.');
        if (parts.Length < 2) return null;
        var payload = parts[1];
        var padLen = 4 - payload.Length % 4;
        if (padLen != 4) payload += new string('=', padLen);
        var json = Convert.FromBase64String(payload);
        return JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(json);
    }
    catch
    {
        return null;
    }
}

// ── Helper: check if token is expired ──
static bool IsTokenExpired(string token)
{
    var payload = DecodeJwtPayload(token);
    if (payload is null) return true;
    if (!payload.TryGetValue("exp", out var expEl)) return false;
    var exp = expEl.GetInt64();
    return DateTimeOffset.FromUnixTimeSeconds(exp) < DateTimeOffset.UtcNow;
}

// ── Helper: format remaining time ──
static string FormatExpiry(string token)
{
    var payload = DecodeJwtPayload(token);
    if (payload is null || !payload.TryGetValue("exp", out var expEl)) return "unknown";
    var exp = DateTimeOffset.FromUnixTimeSeconds(expEl.GetInt64());
    var remaining = exp - DateTimeOffset.UtcNow;
    if (remaining.TotalSeconds <= 0) return "expired";
    if (remaining.TotalDays >= 1) return $"expires in {(int)remaining.TotalDays}d {remaining.Hours}h";
    if (remaining.TotalHours >= 1) return $"expires in {(int)remaining.TotalHours}h {remaining.Minutes}m";
    return $"expires in {remaining.Minutes}m";
}

// ── CLI Definition ──
var rootCommand = new RootCommand("Corterm Worker — remote terminal agent");

// ── login command ──
var loginCommand = new Command("login", "Authenticate with a gateway");
loginCommand.SetAction(async (ParseResult parseResult, CancellationToken cancellationToken) =>
{
    var gatewayUrl = ResolveGatewayUrl(installDir);
    var gatewayBaseUrl = new Uri(gatewayUrl);

    Console.WriteLine();
    Console.WriteLine($"  Gateway: {gatewayUrl}");
    Console.WriteLine();

    var tokenStore = new FileWorkerTokenStore(installDir);
    var handler = new SocketsHttpHandler
    {
        ConnectTimeout = TimeSpan.FromSeconds(10),
        Proxy = HttpClient.DefaultProxy,
        UseProxy = true,
    };
    using var httpClient = new HttpClient(handler)
    {
        BaseAddress = gatewayBaseUrl,
        Timeout = TimeSpan.FromSeconds(30),
    };
    var loginService = new DeviceFlowLoginService(httpClient, tokenStore);
    await loginService.LoginAsync(cancellationToken);
});

// ── logout command ──
var logoutCommand = new Command("logout", "Clear saved credentials");
logoutCommand.SetAction(async (ParseResult parseResult, CancellationToken cancellationToken) =>
{
    var tokenStore = new FileWorkerTokenStore(installDir);
    await tokenStore.ClearAsync(cancellationToken);
    Console.WriteLine("  Logged out. Run 'corterm login' to authenticate.");
});

// ── status command ──
var statusCommand = new Command("status", "Show authentication and connection status");
statusCommand.SetAction((ParseResult parseResult) =>
{
    var gatewayUrl = ResolveGatewayUrl(installDir);
    var workerId = ResolveWorkerId();
    var tokenStore = new FileWorkerTokenStore(installDir);
    var token = tokenStore.GetAccessTokenAsync(CancellationToken.None).GetAwaiter().GetResult();

    Console.WriteLine($"  Gateway: {gatewayUrl}");
    Console.WriteLine($"  Worker:  {workerId}");

    if (string.IsNullOrWhiteSpace(token))
    {
        Console.WriteLine("  Status:  Not authenticated");
    }
    else
    {
        var payload = DecodeJwtPayload(token);
        var username = payload?.TryGetValue("unique_name", out var nameEl) == true
            ? nameEl.GetString()
            : payload?.TryGetValue("sub", out var subEl) == true
                ? subEl.GetString()
                : null;
        var expiry = FormatExpiry(token);
        Console.WriteLine($"  Status:  Authenticated{(username is not null ? $" ({username})" : "")} ({expiry})");
    }
});

// ── doctor command ──
var doctorCommand = new Command("doctor", "Diagnose connectivity and configuration issues");
doctorCommand.SetAction(async (ParseResult parseResult, CancellationToken cancellationToken) =>
{
    var gatewayUrl = ResolveGatewayUrl(installDir);
    var workerId = ResolveWorkerId();
    var tokenStore = new FileWorkerTokenStore(installDir);

    Console.WriteLine("  Checking Corterm Worker...");
    Console.WriteLine();

    var failed = 0;

    // Check 1: Gateway URL
    Console.WriteLine($"  [\u2713] Gateway URL: {gatewayUrl}");

    // Check 2: Gateway reachable
    var gatewayBaseUrl = new Uri(gatewayUrl);
    try
    {
        using var handler = new SocketsHttpHandler { ConnectTimeout = TimeSpan.FromSeconds(5), Proxy = HttpClient.DefaultProxy, UseProxy = true };
        using var http = new HttpClient(handler) { BaseAddress = gatewayBaseUrl, Timeout = TimeSpan.FromSeconds(5) };
        var sw = System.Diagnostics.Stopwatch.StartNew();
        await http.GetAsync("/api/auth/device-flow", cancellationToken);
        sw.Stop();
        Console.WriteLine($"  [\u2713] Gateway reachable (latency: {sw.ElapsedMilliseconds}ms)");
    }
    catch (Exception ex)
    {
        failed++;
        Console.WriteLine($"  [\u2717] Gateway unreachable ({ex.InnerException?.Message ?? ex.Message})");
    }

    // Check 3: Auth token present
    var token = await tokenStore.GetAccessTokenAsync(cancellationToken);
    if (!string.IsNullOrWhiteSpace(token))
    {
        Console.WriteLine("  [\u2713] Auth token present");

        // Check 4: Auth token valid
        if (IsTokenExpired(token))
        {
            failed++;
            Console.WriteLine("  [\u2717] Auth token expired");
        }
        else
        {
            Console.WriteLine($"  [\u2713] Auth token valid ({FormatExpiry(token)})");
        }
    }
    else
    {
        failed++;
        Console.WriteLine("  [\u2717] Auth token missing");
    }

    // Check 5: Worker ID
    Console.WriteLine($"  [\u2713] Worker ID: {workerId}");

    // Check 6: PTY support
    try
    {
        var ptyHost = new UnixPtyHost();
        var process = await ptyHost.StartAsync(80, 24, cancellationToken);
        await process.DisposeAsync();
        Console.WriteLine("  [\u2713] PTY support: available");
    }
    catch (Exception ex)
    {
        failed++;
        Console.WriteLine($"  [\u2717] PTY support: unavailable ({ex.Message})");
    }

    Console.WriteLine();
    if (failed == 0)
    {
        Console.WriteLine("  All checks passed.");
    }
    else
    {
        Console.WriteLine($"  {failed} check(s) failed. Run 'corterm login' to re-authenticate.");
        Environment.ExitCode = 1;
    }
});

// ── root command (default: start worker daemon) ──
rootCommand.SetAction(async (ParseResult parseResult, CancellationToken cancellationToken) =>
{
    var gatewayUrl = ResolveGatewayUrl(installDir);
    var gatewayBaseUrl = new Uri(gatewayUrl);
    var workerId = ResolveWorkerId();

    var tokenStore = new FileWorkerTokenStore(installDir);
    var savedToken = await tokenStore.GetAccessTokenAsync(cancellationToken);

    if (string.IsNullOrWhiteSpace(savedToken))
    {
        Console.Error.WriteLine("  Worker is not authenticated. Run 'corterm login' first.");
        Console.Error.WriteLine($"  Gateway: {gatewayUrl}");
        Environment.ExitCode = 1;
        return;
    }

    var currentToken = savedToken;

    // Print startup banner
    Console.WriteLine($"Corterm Worker {version}");
    Console.WriteLine($"  Gateway: {gatewayUrl}");
    Console.WriteLine($"  Worker:  {workerId}");

    var builder = Host.CreateApplicationBuilder();

    // Prevent ConsoleLifetime from reading stdin — the worker is a daemon
    // and should not interact with the terminal's input stream.
    Console.SetIn(TextReader.Null);

    // Suppress verbose framework logging — only show warnings and errors
    builder.Logging.SetMinimumLevel(LogLevel.Warning);

    builder.Services.AddSingleton<IPtyHost, UnixPtyHost>();
    builder.Services.AddSingleton<IWorkerGatewayClient>(_ =>
    {
        var connection = new HubConnectionBuilder()
            .WithUrl(new Uri(gatewayBaseUrl, "/hubs/worker"), options =>
            {
                options.AccessTokenProvider = () => Task.FromResult<string?>(currentToken);
                options.Proxy = HttpClient.DefaultProxy;
            })
            .AddMessagePackProtocol()
            .WithAutomaticReconnect()
            .Build();

        return new WorkerGatewayClient(connection);
    });

    // Background service that refreshes the token every 24 hours
    var refreshHandler = new SocketsHttpHandler
    {
        Proxy = HttpClient.DefaultProxy,
        UseProxy = true,
    };
    builder.Services.AddSingleton(_ => new HttpClient(refreshHandler) { BaseAddress = gatewayBaseUrl });
    builder.Services.AddHostedService<TokenRefreshService>(sp =>
    {
        var httpClient = sp.GetRequiredService<HttpClient>();
        return new TokenRefreshService(httpClient, tokenStore, () => currentToken, t => currentToken = t);
    });

    builder.Services.AddHostedService(services => new WorkerRuntimeHost(
        workerId,
        services.GetRequiredService<IWorkerGatewayClient>(),
        services.GetRequiredService<IPtyHost>(),
        services.GetRequiredService<ILoggerFactory>()));

    await builder.Build().RunAsync(cancellationToken);
});

// ── update command ──
var updateCommand = new Command("update", "Update Corterm Worker to the latest version");
updateCommand.SetAction(async (ParseResult parseResult, CancellationToken cancellationToken) =>
{
    Console.WriteLine($"  Current version: {version}");
    Console.WriteLine("  Checking for updates...");

    var githubRepo = "monster-echo/CortexTerminal2";
    var isWindows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);
    var isOsx = RuntimeInformation.IsOSPlatform(OSPlatform.OSX);
    var arch = RuntimeInformation.ProcessArchitecture == Architecture.Arm64 ? "arm64" : "x64";
    var ridOs = isOsx ? "osx" : isWindows ? "win" : "linux";
    var ext = isWindows ? "zip" : "tar.gz";
    var assetName = $"corterm-{ridOs}-{arch}.{ext}";
    var githubProxy = Environment.GetEnvironmentVariable("CORTERM_GITHUB_PROXY") ?? "https://proxy.0x2a.top";

    using var http = new HttpClient(new SocketsHttpHandler { Proxy = HttpClient.DefaultProxy, UseProxy = true });
    http.DefaultRequestHeaders.UserAgent.Add(new System.Net.Http.Headers.ProductInfoHeaderValue("Corterm", version));

    // Fetch latest release version
    string? latestVersion;
    try
    {
        using var resp = await http.GetAsync($"https://api.github.com/repos/{githubRepo}/releases", cancellationToken);
        if (!resp.IsSuccessStatusCode)
        {
            Console.Error.WriteLine($"  Failed to fetch releases: {(int)resp.StatusCode} {resp.ReasonPhrase}");
            Environment.ExitCode = 1;
            return;
        }
        using var doc = await JsonDocument.ParseAsync(await resp.Content.ReadAsStreamAsync(cancellationToken));
        latestVersion = null;
        foreach (var release in doc.RootElement.EnumerateArray())
        {
            if (!release.TryGetProperty("tag_name", out var tagEl)) continue;
            var tag = tagEl.GetString() ?? "";
            if (tag.StartsWith("worker-v"))
            {
                latestVersion = tag["worker-v".Length..];
                break;
            }
        }
    }
    catch (Exception ex)
    {
        Console.Error.WriteLine($"  Failed to check for updates: {ex.Message}");
        Environment.ExitCode = 1;
        return;
    }

    if (string.IsNullOrEmpty(latestVersion))
    {
        Console.Error.WriteLine("  Could not determine latest worker version.");
        Environment.ExitCode = 1;
        return;
    }

    // Normalize for comparison (strip trailing .0)
    var currentNorm = version.Replace(".0", "").TrimEnd('.');
    var latestNorm = latestVersion.Replace(".0", "").TrimEnd('.');
    if (currentNorm == latestNorm)
    {
        Console.WriteLine($"  Already up to date ({version}).");
        return;
    }

    Console.WriteLine($"  New version available: {latestVersion}");

    // Download
    var downloadUrl = $"{githubProxy}/https://github.com/{githubRepo}/releases/latest/download/{assetName}";
    var tmpDir = Path.Combine(Path.GetTempPath(), $"corterm-update-{Guid.NewGuid():N}");
    Directory.CreateDirectory(tmpDir);
    var tmpFile = Path.Combine(tmpDir, isWindows ? "corterm.zip" : "corterm.tar.gz");

    try
    {
        Console.WriteLine($"  Downloading {assetName}...");
        var data = await http.GetByteArrayAsync(downloadUrl, cancellationToken);
        await File.WriteAllBytesAsync(tmpFile, data, cancellationToken);
        Console.WriteLine($"  Download complete ({data.Length} bytes).");

        // Extract
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
            if (tar is not null) await tar.WaitForExitAsync(cancellationToken);
        }

        var newBinary = Path.Combine(extractDir, isWindows ? "corterm.exe" : "corterm");
        if (!File.Exists(newBinary))
        {
            Console.Error.WriteLine($"  Error: binary not found in archive at {newBinary}");
            Environment.ExitCode = 1;
            return;
        }

        var currentBinary = Process.GetCurrentProcess().MainModule?.FileName
            ?? throw new InvalidOperationException("Cannot determine current process path.");
        var backupPath = currentBinary + ".bak";

        if (File.Exists(backupPath)) File.Delete(backupPath);
        File.Move(currentBinary, backupPath);
        File.Copy(newBinary, currentBinary, overwrite: true);
        if (!isWindows)
        {
            try { File.SetUnixFileMode(currentBinary, UnixFileMode.UserExecute | UnixFileMode.GroupExecute | UnixFileMode.OtherRead | UnixFileMode.UserRead | UnixFileMode.GroupRead); } catch { }
        }

        try { File.Delete(backupPath); } catch { }

        Console.WriteLine($"  Updated to {latestVersion}. Restart the worker to apply.");
    }
    finally
    {
        try { if (Directory.Exists(tmpDir)) Directory.Delete(tmpDir, recursive: true); } catch { }
    }
});

rootCommand.Subcommands.Add(loginCommand);
rootCommand.Subcommands.Add(logoutCommand);
rootCommand.Subcommands.Add(statusCommand);
rootCommand.Subcommands.Add(doctorCommand);
rootCommand.Subcommands.Add(updateCommand);

return await rootCommand.Parse(args).InvokeAsync();

public partial class Program;
