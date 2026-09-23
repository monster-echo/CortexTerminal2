using System.CommandLine;
using System.Diagnostics;
using System.Net.Http.Json;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Nodes;
using CortexTerminal.Worker;
using CortexTerminal.Worker.Agent;
using CortexTerminal.Worker.Agent.Adapters;
using CortexTerminal.Worker.Auth;
using CortexTerminal.Worker.Logging;
using CortexTerminal.Worker.Pty;
using CortexTerminal.Worker.Registration;
using CortexTerminal.Worker.RemoteFiles;
using CortexTerminal.Worker.Runtime;
using CortexTerminal.Worker.Tunnels;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Console;

var installDir = AppContext.BaseDirectory;
var version = Assembly.GetEntryAssembly()?.GetName().Version?.ToString(3) ?? "0.0.0";

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
        // JWT payloads are base64url-encoded ('-'/'_' instead of '+'/'/', no padding).
        var payload = parts[1].Replace('-', '+').Replace('_', '/');
        var padLen = 4 - payload.Length % 4;
        if (padLen != 4) payload += new string('=', padLen);
        var json = Convert.FromBase64String(payload);
        // JsonSerializer.Deserialize<Dictionary<string,JsonElement>> is reflection-based and
        // disabled under PublishTrimmed (the type isn't registered in WorkerJsonContext, so it
        // throws InvalidOperationException at runtime). JsonDocument is reflection-free and trims.
        using var doc = JsonDocument.Parse(json);
        var claims = new Dictionary<string, JsonElement>();
        foreach (var prop in doc.RootElement.EnumerateObject())
            claims[prop.Name] = prop.Value.Clone();
        return claims;
    }
    catch
    {
        return null;
    }
}

// ── Helper: run OS service command (start/stop/restart) ──
static (bool Ok, string Message, string? Error) RunServiceCommand(string action)
{
    var isOsx = RuntimeInformation.IsOSPlatform(OSPlatform.OSX);
    var isWindows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);
    var homeDir = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    var plistPath = Path.Combine(homeDir, "Library/LaunchAgents/com.corterm.worker.plist");

    string program, args;
    if (isWindows)
    {
        program = action switch
        {
            "start" => "schtasks",
            "stop" => "taskkill",
            "restart" => "cmd",
            _ => throw new InvalidOperationException($"Unknown action: {action}")
        };
        args = action switch
        {
            "start" => "/run /tn \"Corterm Worker\"",
            "stop" => "/IM corterm.exe /F",
            "restart" => "/c \"taskkill /IM corterm.exe /F & schtasks /run /tn \\\"Corterm Worker\\\"\"",
            _ => ""
        };
    }
    else if (isOsx)
    {
        program = "launchctl";
        args = action switch
        {
            "start" => $"load \"{plistPath}\"",
            "stop" => $"unload \"{plistPath}\"",
            "restart" => $"unload \"{plistPath}\" && launchctl load \"{plistPath}\"",
            _ => ""
        };
    }
    else
    {
        program = "systemctl";
        args = $"--user {action} corterm-worker";
    }

    using var proc = Process.Start(new ProcessStartInfo(program, args)
    {
        UseShellExecute = false,
        RedirectStandardError = true
    });
    if (proc is null)
    {
        return (false, "", $"Failed to run: {program} {args}");
    }
    proc.WaitForExit();
    if (proc.ExitCode != 0)
    {
        var stderr = proc.StandardError.ReadToEnd();
        return (false, "", $"Failed to {action} worker (exit code {proc.ExitCode}).{(!string.IsNullOrEmpty(stderr) ? $"\n  {stderr.Trim()}" : "")}");
    }
    return (true, $"Worker {action}ed.", null);
}

// ── Helper: run a service action command, rendering JSON or human output ──
static int RunServiceAction(ParseResult parseResult, string action, bool json)
{
    var result = RunServiceCommand(action);
    if (json)
    {
        Console.Out.WriteLine(CliJson.Service(action, result.Ok, result.Message, result.Error).ToJsonString());
    }
    else
    {
        Console.WriteLine(result.Message);
        if (!result.Ok && result.Error is not null) Console.Error.WriteLine(result.Error);
    }
    return result.Ok ? 0 : 1;
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

// ── Helper: format worker uptime ──
static string FormatUptime(TimeSpan u) => $"{(int)u.TotalDays}d {u.Hours}h {u.Minutes}m";

// ── CLI Definition ──
var rootCommand = new RootCommand("Corterm Worker — remote terminal agent");

// Helper: build a `--json` option (one instance per subcommand). Root-level options in
// System.CommandLine 2.0.7 are only parsed when they precede the subcommand, which would
// force the awkward `corterm --json status` form — so each subcommand gets its own.
static Option<bool> CreateJsonOption() => new Option<bool>("json", "--json") { Description = "Emit machine-readable JSON to stdout" };

// ── login command ──
var loginCommand = new Command("login", "Authenticate with a gateway");
var loginJson = CreateJsonOption();
loginCommand.Add(loginJson);
loginCommand.SetAction(async (ParseResult parseResult, CancellationToken cancellationToken) =>
{
    var json = parseResult.GetValue(loginJson);
    var gatewayUrl = ResolveGatewayUrl(installDir);
    var gatewayBaseUrl = new Uri(gatewayUrl);

    if (json)
    {
        Console.Error.WriteLine($"Gateway: {gatewayUrl}");
    }
    else
    {
        Console.WriteLine();
        Console.WriteLine($"  Gateway: {gatewayUrl}");
        Console.WriteLine();
    }

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
    if (json)
    {
        await loginService.LoginAsync(cancellationToken, stage =>
        {
            Console.Out.WriteLine(CliJson.LoginStage(
                stage.Stage,
                stage.VerificationUri,
                stage.UserCode,
                stage.ExpiresInSeconds,
                stage.PollIntervalSeconds,
                stage.Message).ToJsonString());
            Console.Out.Flush();
        });
    }
    else
    {
        await loginService.LoginAsync(cancellationToken);
    }
});

// ── logout command ──
var logoutCommand = new Command("logout", "Clear saved credentials");
var logoutJson = CreateJsonOption();
logoutCommand.Add(logoutJson);
logoutCommand.SetAction(async (ParseResult parseResult, CancellationToken cancellationToken) =>
{
    var json = parseResult.GetValue(logoutJson);
    var tokenStore = new FileWorkerTokenStore(installDir);
    await tokenStore.ClearAsync(cancellationToken);
    if (json)
    {
        Console.Out.WriteLine(CliJson.Logout(true, "Logged out. Run 'corterm login' to authenticate.").ToJsonString());
    }
    else
    {
        Console.WriteLine("  Logged out. Run 'corterm login' to authenticate.");
    }
});

// ── status command ──
var statusCommand = new Command("status", "Show authentication and connection status");
var statusJson = CreateJsonOption();
statusCommand.Add(statusJson);
statusCommand.SetAction((ParseResult parseResult) =>
{
    var json = parseResult.GetValue(statusJson);
    var gatewayUrl = ResolveGatewayUrl(installDir);
    var workerId = ResolveWorkerId();
    var tokenStore = new FileWorkerTokenStore(installDir);
    var token = tokenStore.GetAccessTokenAsync(CancellationToken.None).GetAwaiter().GetResult();

    // Uptime comes from the daemon's recorded start time (.worker-state); `status` is a
    // separate short-lived process whose own StartTime is always ~0.
    var statePath = Path.Combine(installDir, ".worker-state");
    var uptimeText = File.Exists(statePath) && long.TryParse(File.ReadAllText(statePath).Trim(), out var startedAt)
        ? FormatUptime(DateTimeOffset.UtcNow - DateTimeOffset.FromUnixTimeSeconds(startedAt))
        : "n/a";

    var authenticated = !string.IsNullOrWhiteSpace(token);
    string? user = null;
    string? authExpiry = null;
    if (authenticated)
    {
        var payload = DecodeJwtPayload(token!);
        user = payload?.TryGetValue("unique_name", out var nameEl) == true
            ? nameEl.GetString()
            : payload?.TryGetValue("sub", out var subEl) == true
                ? subEl.GetString()
                : null;
        authExpiry = FormatExpiry(token!);
    }

    // Fetch gateway info and worker list (tolerating network errors)
    JsonObject? gatewayInfo = null;
    var updateAvailable = false;
    var workersList = new List<JsonObject>();
    if (authenticated)
    {
        try
        {
            using var http = new HttpClient(new SocketsHttpHandler { Proxy = HttpClient.DefaultProxy, UseProxy = true });
            http.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
            http.Timeout = TimeSpan.FromSeconds(5);

            // JsonDocument.ParseAsync is reflection-free and trims safely. GetFromJsonAsync<JsonElement>
            // is reflection-based and throws under PublishTrimmed (JsonSerializer.IsReflectionEnabledByDefault
            // is false) — the original `corterm status` swallowed this and never showed gateway info/workers.
            using (var infoResp = http.GetAsync($"{gatewayUrl}/api/gateway/info").GetAwaiter().GetResult())
            using (var infoDoc = JsonDocument.ParseAsync(infoResp.Content.ReadAsStream()).GetAwaiter().GetResult())
            {
                var infoRoot = infoDoc.RootElement;
                var gVersion = infoRoot.TryGetProperty("version", out var gv) ? gv.GetString() : null;
                var latestWorker = infoRoot.TryGetProperty("latestWorkerVersion", out var lw) ? lw.GetString() : null;
                gatewayInfo = new JsonObject { ["version"] = gVersion, ["latestWorkerVersion"] = latestWorker };
                updateAvailable = latestWorker is not null && latestWorker.Replace(".0", "") != version.Replace(".0", "");
            }

            using (var workersResp = http.GetAsync($"{gatewayUrl}/api/me/workers").GetAwaiter().GetResult())
            using (var workersDoc = JsonDocument.ParseAsync(workersResp.Content.ReadAsStream()).GetAwaiter().GetResult())
            {
                var workersRoot = workersDoc.RootElement;
                if (workersRoot.ValueKind == JsonValueKind.Array)
                {
                    foreach (var w in workersRoot.EnumerateArray())
                    {
                        workersList.Add(CliJson.Worker(
                            w.TryGetProperty("workerId", out var wid) ? wid.GetString() ?? "" : "",
                            w.TryGetProperty("name", out var n) ? n.GetString() : null,
                            w.TryGetProperty("hostname", out var hn) ? hn.GetString() : null,
                            w.TryGetProperty("operatingSystem", out var osEl) ? osEl.GetString() : null,
                            w.TryGetProperty("architecture", out var ar) ? ar.GetString() : null,
                            w.TryGetProperty("version", out var wv) ? wv.GetString() : null,
                            w.TryGetProperty("isOnline", out var on) && on.GetBoolean(),
                            w.TryGetProperty("lastSeenAtUtc", out var ls) ? ls.GetString() : null,
                            w.TryGetProperty("sessionCount", out var sc) && sc.ValueKind == JsonValueKind.Number ? sc.GetInt32() : null,
                            w.TryGetProperty("cpuUsagePercent", out var cpu) && cpu.ValueKind == JsonValueKind.Number ? cpu.GetDouble() : null,
                            w.TryGetProperty("memoryUsagePercent", out var mem) && mem.ValueKind == JsonValueKind.Number ? mem.GetDouble() : null));
                    }
                }
            }
        }
        catch (Exception ex)
        {
            if (json) Console.Error.WriteLine($"status: gateway fetch failed: {ex}");
            // Network errors should not block status display
        }
    }

    var workers = new JsonArray();
    foreach (var w in workersList) workers.Add((JsonNode)w);

    if (json)
    {
        Console.Out.WriteLine(CliJson.Status(
            version, Environment.ProcessId, uptimeText, gatewayUrl, workerId,
            authenticated, user, authExpiry, gatewayInfo, updateAvailable, workers).ToJsonString());
        return;
    }

    Console.WriteLine($"  Version: {version}");
    Console.WriteLine($"  PID:     {Environment.ProcessId}");
    Console.WriteLine($"  Uptime:  {uptimeText}");
    Console.WriteLine($"  Gateway: {gatewayUrl}");
    Console.WriteLine($"  Worker:  {workerId}");

    if (!authenticated)
    {
        Console.WriteLine("  Status:  Not authenticated");
    }
    else
    {
        Console.WriteLine($"  User:    {user ?? "unknown"}");
        Console.WriteLine($"  Status:  Authenticated ({authExpiry})");

        if (gatewayInfo is not null)
        {
            Console.WriteLine();
            var gVersion = gatewayInfo["version"]?.GetValue<string>();
            var latestWorker = gatewayInfo["latestWorkerVersion"]?.GetValue<string>();
            Console.WriteLine("  Gateway Version: " + (gVersion ?? "—"));
            if (latestWorker is not null)
                Console.WriteLine($"  Latest Worker:   {latestWorker}{(updateAvailable ? "  (update available)" : "")}");
        }

        if (workersList.Count > 0)
        {
            Console.WriteLine();
            Console.WriteLine("  Workers:");
            foreach (var w in workersList)
            {
                var name = w["name"]?.GetValue<string>() ?? w["workerId"]?.GetValue<string>() ?? "?";
                var isOnline = w["isOnline"]?.GetValue<bool>() ?? false;
                var wVer = w["version"]?.GetValue<string>() ?? "—";
                var os = w["operatingSystem"]?.GetValue<string>() ?? "";
                var statusIcon = isOnline ? "●" : "○";
                Console.WriteLine($"    {statusIcon} {name}  v{wVer}  {os}{(!isOnline ? "  (offline)" : "")}");
            }
        }
    }
});

// ── doctor command ──
var doctorCommand = new Command("doctor", "Diagnose connectivity and configuration issues");
var doctorJson = CreateJsonOption();
doctorCommand.Add(doctorJson);
doctorCommand.SetAction(async (ParseResult parseResult, CancellationToken cancellationToken) =>
{
    var json = parseResult.GetValue(doctorJson);
    var gatewayUrl = ResolveGatewayUrl(installDir);
    var workerId = ResolveWorkerId();
    var tokenStore = new FileWorkerTokenStore(installDir);

    if (!json)
    {
        Console.WriteLine("  Checking Corterm Worker...");
        Console.WriteLine();
    }

    var checks = new List<(string Name, bool Ok, string Detail)>();

    // Check 1: Gateway URL
    checks.Add(("Gateway URL", true, gatewayUrl));

    // Check 2: Gateway reachable
    var gatewayBaseUrl = new Uri(gatewayUrl);
    try
    {
        using var handler = new SocketsHttpHandler { ConnectTimeout = TimeSpan.FromSeconds(5), Proxy = HttpClient.DefaultProxy, UseProxy = true };
        using var http = new HttpClient(handler) { BaseAddress = gatewayBaseUrl, Timeout = TimeSpan.FromSeconds(5) };
        var sw = System.Diagnostics.Stopwatch.StartNew();
        await http.GetAsync("/api/auth/device-flow", cancellationToken);
        sw.Stop();
        checks.Add(("Gateway reachable", true, $"latency: {sw.ElapsedMilliseconds}ms"));
    }
    catch (Exception ex)
    {
        checks.Add(("Gateway reachable", false, ex.InnerException?.Message ?? ex.Message));
    }

    // Check 3: Auth token present
    var token = await tokenStore.GetAccessTokenAsync(cancellationToken);
    if (!string.IsNullOrWhiteSpace(token))
    {
        checks.Add(("Auth token present", true, "present"));

        // Check 4: Auth token valid
        if (IsTokenExpired(token))
        {
            checks.Add(("Auth token valid", false, "expired"));
        }
        else
        {
            checks.Add(("Auth token valid", true, FormatExpiry(token)));
        }
    }
    else
    {
        checks.Add(("Auth token present", false, "missing"));
    }

    // Check 5: Worker ID
    checks.Add(("Worker ID", true, workerId));

    // Check 6: PTY support
    try
    {
        var ptyHost = new UnixPtyHost();
        var process = await ptyHost.StartAsync(80, 24, cancellationToken);
        await process.DisposeAsync();
        checks.Add(("PTY support", true, "available"));
    }
    catch (Exception ex)
    {
        checks.Add(("PTY support", false, ex.Message));
    }

    var failed = checks.Count(c => !c.Ok);

    if (json)
    {
        Console.Out.WriteLine(CliJson.Doctor(checks).ToJsonString());
    }
    else
    {
        foreach (var (name, ok, detail) in checks)
        {
            var icon = ok ? "[✓]" : "[✗]";
            Console.WriteLine($"  {icon} {name}: {detail}");
        }
        Console.WriteLine();
        if (failed == 0)
        {
            Console.WriteLine("  All checks passed.");
        }
        else
        {
            Console.WriteLine($"  {failed} check(s) failed. Run 'corterm login' to re-authenticate.");
        }
    }

    return failed > 0 ? 1 : 0;
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

    // Record daemon start time so `corterm status` (a separate process) can report real uptime.
    File.WriteAllText(Path.Combine(installDir, ".worker-state"),
        DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString());

    var builder = Host.CreateApplicationBuilder();
    builder.Configuration.AddJsonFile(Path.Combine(installDir, "appsettings.json"), optional: true, reloadOnChange: true);
    builder.Logging.AddConsoleFormatter<CliConsoleFormatter, SimpleConsoleFormatterOptions>();
    builder.Logging.AddConsole(options => options.FormatterName = "cli");

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

    // Agent tracking — loopback HTTP endpoint + adapter registry + dispatch sink.
    // Hook URL is published via AgentIntegration once Kestrel binds.
    builder.Services.AddSingleton(sp => new AgentIntegration(
        installDir,
        sp.GetRequiredService<ILogger<AgentIntegration>>()));
    builder.Services.AddSingleton<IAgentIntegration>(sp => sp.GetRequiredService<AgentIntegration>());
    builder.Services.AddSingleton<IAgentAdapterRegistry>(sp => new AgentAdapterRegistry(
        sp.GetRequiredService<IEnumerable<IAgentAdapter>>(),
        sp.GetRequiredService<ILogger<AgentAdapterRegistry>>()));
    builder.Services.AddSingleton<IAgentAdapter>(sp => new ClaudeCodeAdapter());
    builder.Services.AddSingleton<IAgentEventSink>(sp => new GatewayAgentEventSink(
        sp.GetRequiredService<IWorkerGatewayClient>(),
        sp.GetRequiredService<ILogger<GatewayAgentEventSink>>()));
    builder.Services.AddHostedService(sp => new AgentEventEndpoint(
        sp.GetRequiredService<AgentIntegration>(),
        sp.GetRequiredService<IAgentAdapterRegistry>(),
        sp.GetRequiredService<IAgentEventSink>(),
        sp.GetRequiredService<ILogger<AgentEventEndpoint>>()));

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
        var logger = sp.GetRequiredService<ILogger<TokenRefreshService>>();
        var configuration = sp.GetRequiredService<IConfiguration>();
        var lifetime = sp.GetRequiredService<IHostApplicationLifetime>();
        return new TokenRefreshService(httpClient, tokenStore, () => currentToken, t => currentToken = t, configuration, lifetime, logger);
    });

    // Relay 数据面：隧道持久 WS 反代 + 文件传输执行器 + LAN 直连监听器（端点协商）。
    builder.Services.AddSingleton<RelayLink>(sp => new RelayLink(
        workerId,
        sp.GetRequiredService<ILogger<RelayLink>>(),
        waitPortTimeout: TimeSpan.FromSeconds(
            sp.GetRequiredService<IConfiguration>().GetValue("Tunnels:WaitPortSeconds", 15))));
    builder.Services.AddSingleton(sp => new RelayTransferService(
        50L * 1024 * 1024,
        sp.GetRequiredService<ILogger<RelayTransferService>>()));
    builder.Services.AddSingleton(sp => new LocalTransferListener(
        sp.GetRequiredService<RelayTransferService>(),
        sp.GetRequiredService<IConfiguration>().GetValue("Transfer:ListenPort", 47631),
        sp.GetRequiredService<IConfiguration>()["Transfer:PublicBaseUrl"],
        sp.GetRequiredService<ILogger<LocalTransferListener>>()));
    // 注册顺序即启动顺序：监听器先于运行时宿主绑定端口，LAN 端点才能随首个信息帧上报。
    builder.Services.AddHostedService(sp => sp.GetRequiredService<LocalTransferListener>());

    builder.Services.AddHostedService(services => new WorkerRuntimeHost(
        workerId,
        services.GetRequiredService<IWorkerGatewayClient>(),
        services.GetRequiredService<IPtyHost>(),
        services.GetRequiredService<ILoggerFactory>(),
        services.GetRequiredService<IHostApplicationLifetime>(),
        services.GetRequiredService<RelayLink>(),
        services.GetRequiredService<RelayTransferService>(),
        services.GetRequiredService<LocalTransferListener>(),
        ResolveMetricsCollectorOrNull(services),
        agentIntegration: services.GetService<IAgentIntegration>()));

    static CortexTerminal.Worker.Metrics.ISystemMetricsCollector? ResolveMetricsCollectorOrNull(IServiceProvider services)
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
        {
            return new CortexTerminal.Worker.Metrics.LinuxSystemMetricsCollector(
                services.GetRequiredService<ILogger<CortexTerminal.Worker.Metrics.LinuxSystemMetricsCollector>>());
        }
        if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            return new CortexTerminal.Worker.Metrics.MacSystemMetricsCollector(
                services.GetRequiredService<ILogger<CortexTerminal.Worker.Metrics.MacSystemMetricsCollector>>());
        }
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            return new CortexTerminal.Worker.Metrics.WindowsSystemMetricsCollector(
                services.GetRequiredService<ILogger<CortexTerminal.Worker.Metrics.WindowsSystemMetricsCollector>>());
        }
        services.GetRequiredService<ILogger<Program>>()
            .LogWarning("Metrics disabled: no collector for platform {OS}.", RuntimeInformation.OSDescription);
        return null;
    }

    var host = builder.Build();
    // Self-heal before writing shims: if cortap is missing — the typical state of an install
    // that reached this version via the pre-full-sync update path (which only copied corterm
    // and discarded cortap) — restore the release files for the running version now.
    await EnsureCortapPresentAsync(installDir, version, host.Services.GetRequiredService<ILogger<Program>>(), cancellationToken);
    host.Services.GetRequiredService<AgentIntegration>().EnsureShimsInstalled();
    // Strip the retired corterm-artifacts skill (installed copies, codex section, cache) so
    // upgraded workers stop injecting it into agent prompts. No-op after the first run.
    await CortexTerminal.Worker.Agent.AgentSkillCleanup.RunOnceAsync(
        host.Services.GetRequiredService<ILogger<Program>>(), cancellationToken);
    await host.RunAsync(cancellationToken);
});

// ── self-heal: restore missing release files without replacing the running corterm binary ──

// Checks whether the agent wrapper (cortap) is present; if not, re-downloads the current
// version's release archive and syncs the files. Runs on every startup but is a cheap
// File.Exists no-op once healthy. Failures are logged and swallowed so a missing optional
// wrapper can't keep the whole worker (and its terminal) from starting.
static async Task EnsureCortapPresentAsync(string installDir, string version, ILogger logger, CancellationToken cancellationToken)
{
    var isWindows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);
    var wrapperName = isWindows ? "cortap.exe" : "cortap";
    if (File.Exists(Path.Combine(installDir, wrapperName))) return;

    logger.LogWarning("Agent wrapper {Wrapper} missing; restoring release files for v{Version} ...", wrapperName, version);
    try
    {
        if (await RestoreReleaseFilesAsync(installDir, version, cancellationToken))
            logger.LogInformation("Agent wrapper restored.");
        else
            logger.LogError("Agent wrapper restore failed: release archive had no files to sync.");
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Agent wrapper self-heal failed; agent tracking disabled until next restart.");
    }
}

// Downloads the release archive for `targetVersion`, extracts it, and overwrites every file
// in `installDir` except the running corterm binary (already the right version; on Windows
// also image-locked). cortap and any other missing files land in place. Returns false if the
// archive contained nothing to copy.
static async Task<bool> RestoreReleaseFilesAsync(string installDir, string targetVersion, CancellationToken cancellationToken)
{
    var isWindows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);
    var isOsx = RuntimeInformation.IsOSPlatform(OSPlatform.OSX);
    var arch = RuntimeInformation.ProcessArchitecture == Architecture.Arm64 ? "arm64" : "x64";
    var ridOs = isOsx ? "osx" : isWindows ? "win" : "linux";
    var ext = isWindows ? "zip" : "tar.gz";
    var assetName = $"corterm-{ridOs}-{arch}.{ext}";
    var githubRepo = "monster-echo/CortexTerminal2";
    var githubProxy = Environment.GetEnvironmentVariable("CORTERM_GITHUB_PROXY") ?? "https://proxy.0x2a.top";
    var downloadUrl = $"{githubProxy}/https://github.com/{githubRepo}/releases/download/worker-v{targetVersion}/{assetName}";

    var tmpDir = Path.Combine(Path.GetTempPath(), $"corterm-restore-{Guid.NewGuid():N}");
    Directory.CreateDirectory(tmpDir);
    var tmpFile = Path.Combine(tmpDir, isWindows ? "corterm.zip" : "corterm.tar.gz");

    try
    {
        using var http = new HttpClient(new SocketsHttpHandler { Proxy = HttpClient.DefaultProxy, UseProxy = true });
        var data = await http.GetByteArrayAsync(downloadUrl, cancellationToken);
        await File.WriteAllBytesAsync(tmpFile, data, cancellationToken);

        var extractDir = Path.Combine(tmpDir, "extracted");
        Directory.CreateDirectory(extractDir);
        if (isWindows)
        {
            System.IO.Compression.ZipFile.ExtractToDirectory(tmpFile, extractDir, overwriteFiles: true);
        }
        else
        {
            var tar = Process.Start(new ProcessStartInfo("tar", $"-xzf \"{tmpFile}\" -C \"{extractDir}\"") { UseShellExecute = false });
            if (tar is not null) await tar.WaitForExitAsync(cancellationToken);
        }

        // Full-sync into the install dir, skipping corterm itself (right version + Windows lock).
        // Preserve unix file modes so cortap keeps its exec bit after File.Copy.
        var currentBinaryName = isWindows ? "corterm.exe" : "corterm";
        var restored = false;
        foreach (var sourceFile in Directory.EnumerateFiles(extractDir, "*", SearchOption.TopDirectoryOnly))
        {
            if (Path.GetFileName(sourceFile) == currentBinaryName) continue;
            var destFile = Path.Combine(installDir, Path.GetFileName(sourceFile));
            File.Copy(sourceFile, destFile, overwrite: true);
            if (!isWindows)
            {
                try { File.SetUnixFileMode(destFile, File.GetUnixFileMode(sourceFile)); } catch { }
            }
            restored = true;
        }
        return restored;
    }
    finally
    {
        try { if (Directory.Exists(tmpDir)) Directory.Delete(tmpDir, recursive: true); } catch { }
    }
}

// ── update command ──
var updateCommand = new Command("update", "Update Corterm Worker to the latest version");
var updateJson = CreateJsonOption();
updateCommand.Add(updateJson);
var checkOnly = new Option<bool>("check", "--check") { Description = "Only check for the latest version without downloading" };
updateCommand.Add(checkOnly);
updateCommand.SetAction(async (ParseResult parseResult, CancellationToken cancellationToken) =>
{
    var json = parseResult.GetValue(updateJson);
    var check = parseResult.GetValue(checkOnly);

    // Human text is suppressed in JSON mode so stdout carries only machine-readable JSON.
    var say = (string msg) => { if (!json) Console.WriteLine(msg); };

    say($"  Current version: {version}");
    say("  Checking for updates...");

    var githubRepo = "monster-echo/CortexTerminal2";
    var isWindows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);
    var isOsx = RuntimeInformation.IsOSPlatform(OSPlatform.OSX);
    var isLinux = RuntimeInformation.IsOSPlatform(OSPlatform.Linux);
    if (!isWindows && !isOsx && !isLinux) throw new PlatformNotSupportedException($"Unsupported platform: {RuntimeInformation.OSDescription}");
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
            if (json) Console.Out.WriteLine(CliJson.UpdateStage("error", message: $"Failed to fetch releases: {(int)resp.StatusCode} {resp.ReasonPhrase}").ToJsonString());
            Console.Error.WriteLine($"  Failed to fetch releases: {(int)resp.StatusCode} {resp.ReasonPhrase}");
            return 1;
        }
        using var doc = await JsonDocument.ParseAsync(await resp.Content.ReadAsStreamAsync(cancellationToken));
        latestVersion = null;
        Version? best = null;
        foreach (var release in doc.RootElement.EnumerateArray())
        {
            if (!release.TryGetProperty("tag_name", out var tagEl)) continue;
            var tag = tagEl.GetString() ?? "";
            if (!tag.StartsWith("worker-v")) continue;
            var ver = tag["worker-v".Length..];
            // GitHub's /releases list is NOT strictly ordered by version or date — a newer
            // release can appear below an older one (observed: v0.5.10 listed under v0.5.9).
            // Pick the highest semver across all returned releases, not the first one.
            if (!Version.TryParse(ver, out var parsed)) continue;
            if (best is null || parsed > best)
            {
                best = parsed;
                latestVersion = ver;
            }
        }
    }
    catch (Exception ex)
    {
        if (json) Console.Out.WriteLine(CliJson.UpdateStage("error", message: $"Failed to check for updates: {ex.Message}").ToJsonString());
        Console.Error.WriteLine($"  Failed to check for updates: {ex.Message}");
        return 1;
    }

    if (string.IsNullOrEmpty(latestVersion))
    {
        if (json) Console.Out.WriteLine(CliJson.UpdateStage("error", message: "Could not determine latest worker version.").ToJsonString());
        Console.Error.WriteLine("  Could not determine latest worker version.");
        return 1;
    }

    // --check: report the latest version without downloading anything
    if (check)
    {
        var updateAvailable = latestVersion != version;
        var checkDownloadUrl = $"{githubProxy}/https://github.com/{githubRepo}/releases/latest/download/{assetName}";
        if (json)
        {
            Console.Out.WriteLine(CliJson.UpdateCheck(version, latestVersion, updateAvailable, assetName, checkDownloadUrl).ToJsonString());
        }
        else
        {
            Console.WriteLine($"  Latest version: {latestVersion}");
            Console.WriteLine(updateAvailable
                ? $"  Update available: {assetName}"
                : $"  Already up to date ({version}).");
            Console.WriteLine($"  Download: {checkDownloadUrl}");
        }
        return 0;
    }

    // Even when already on the latest version, an install that arrived here via the
    // pre-full-sync update path is missing cortap. Re-sync instead of short-circuiting so
    // `corterm update` self-heals — otherwise these installs are stuck (no newer version to
    // upgrade into, and the version-equality path used to just return).
    var wrapperName = isWindows ? "cortap.exe" : "cortap";
    var wrapperMissing = !File.Exists(Path.Combine(installDir, wrapperName));
    if (version == latestVersion)
    {
        if (!wrapperMissing)
        {
            if (json) Console.Out.WriteLine(CliJson.UpdateStage("done", version: version, message: "Already up to date.").ToJsonString());
            else say($"  Already up to date ({version}).");
            return 0;
        }
        say($"  Already on {version}, but {wrapperName} is missing — re-syncing release files ...");
        if (json) Console.Out.WriteLine(CliJson.UpdateStage("check", version: version, message: $"{wrapperName} missing, re-syncing").ToJsonString());
        try
        {
            await RestoreReleaseFilesAsync(installDir, version, cancellationToken);
            say($"  {wrapperName} restored. Restarting worker ...");
            if (json) Console.Out.WriteLine(CliJson.UpdateStage("install", version: version, message: $"{wrapperName} restored").ToJsonString());
            var svc = RunServiceCommand("restart");
            if (!svc.Ok)
            {
                if (json) Console.Out.WriteLine(CliJson.UpdateStage("error", message: svc.Error).ToJsonString());
                Console.Error.WriteLine(svc.Error);
                return 1;
            }
            if (json) Console.Out.WriteLine(CliJson.UpdateStage("done", version: version).ToJsonString());
        }
        catch (Exception ex)
        {
            if (json) Console.Out.WriteLine(CliJson.UpdateStage("error", message: $"Failed to restore {wrapperName}: {ex.Message}").ToJsonString());
            Console.Error.WriteLine($"  Failed to restore {wrapperName}: {ex.Message}");
            return 1;
        }
        return 0;
    }

    say($"  New version available: {latestVersion}");
    if (json) Console.Out.WriteLine(CliJson.UpdateStage("check", version: latestVersion).ToJsonString());

    // Download
    var downloadUrl = $"{githubProxy}/https://github.com/{githubRepo}/releases/latest/download/{assetName}";
    var tmpDir = Path.Combine(Path.GetTempPath(), $"corterm-update-{Guid.NewGuid():N}");
    Directory.CreateDirectory(tmpDir);
    var tmpFile = Path.Combine(tmpDir, isWindows ? "corterm.zip" : "corterm.tar.gz");

    try
    {
        say($"  Downloading {assetName}...");
        if (json) Console.Out.WriteLine(CliJson.UpdateStage("download", bytes: 0, message: assetName).ToJsonString());
        var data = await http.GetByteArrayAsync(downloadUrl, cancellationToken);
        await File.WriteAllBytesAsync(tmpFile, data, cancellationToken);
        say($"  Download complete ({data.Length} bytes).");
        if (json) Console.Out.WriteLine(CliJson.UpdateStage("download", bytes: data.Length, message: assetName).ToJsonString());

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
        say("  Extracting...");
        if (json) Console.Out.WriteLine(CliJson.UpdateStage("extract").ToJsonString());

        var newBinary = Path.Combine(extractDir, isWindows ? "corterm.exe" : "corterm");
        if (!File.Exists(newBinary))
        {
            if (json) Console.Out.WriteLine(CliJson.UpdateStage("error", message: $"Binary not found in archive at {newBinary}").ToJsonString());
            Console.Error.WriteLine($"  Error: binary not found in archive at {newBinary}");
            return 1;
        }

        var currentBinary = Process.GetCurrentProcess().MainModule?.FileName
            ?? throw new InvalidOperationException("Cannot determine current process path.");
        var installDir = Path.GetDirectoryName(currentBinary)
            ?? throw new InvalidOperationException("Cannot determine install directory.");
        var backupPath = currentBinary + ".bak";

        // Replace the running corterm binary. Windows holds an image lock on the running
        // exe, so rename it aside (.bak) and write the new one into the original path —
        // the classic self-overwrite trick. Other files have no such lock and are copied
        // in the loop below.
        if (File.Exists(backupPath)) File.Delete(backupPath);
        File.Move(currentBinary, backupPath);
        File.Copy(newBinary, currentBinary, overwrite: true);
        if (!isWindows)
        {
            try { File.SetUnixFileMode(currentBinary, UnixFileMode.UserExecute | UnixFileMode.GroupExecute | UnixFileMode.OtherRead | UnixFileMode.UserRead | UnixFileMode.GroupRead); } catch { }
        }
        try { File.Delete(backupPath); } catch { }

        // Sync the rest of the release archive over the install dir so an upgrade matches
        // a fresh install — cortap, appsettings, service templates, etc. all refresh.
        // Without this, a worker that predates cortap-in-archive (commit feeb091) never
        // gains the wrapper and the shims written at startup point at a missing file.
        // Preserve unix file modes per file so cortap keeps its exec bit (File.Copy resets
        // mode to umask). The archive is flat (single-file publish), so top-level is enough.
        var currentBinaryName = Path.GetFileName(currentBinary);
        foreach (var sourceFile in Directory.EnumerateFiles(extractDir, "*", SearchOption.TopDirectoryOnly))
        {
            if (Path.GetFileName(sourceFile) == currentBinaryName) continue;  // corterm already replaced
            var destFile = Path.Combine(installDir, Path.GetFileName(sourceFile));
            File.Copy(sourceFile, destFile, overwrite: true);
            if (!isWindows)
            {
                try { File.SetUnixFileMode(destFile, File.GetUnixFileMode(sourceFile)); } catch { }
            }
        }

        say($"  Updated to {latestVersion}. Restarting worker ...");
        if (json) Console.Out.WriteLine(CliJson.UpdateStage("install", version: latestVersion).ToJsonString());

        var svcResult = RunServiceCommand("restart");
        if (!svcResult.Ok)
        {
            if (json) Console.Out.WriteLine(CliJson.UpdateStage("error", message: svcResult.Error).ToJsonString());
            Console.Error.WriteLine(svcResult.Error);
            return 1;
        }
        if (json) Console.Out.WriteLine(CliJson.UpdateStage("done", version: latestVersion).ToJsonString());
    }
    catch (Exception ex)
    {
        if (json) Console.Out.WriteLine(CliJson.UpdateStage("error", message: ex.Message).ToJsonString());
        Console.Error.WriteLine($"  Update failed: {ex.Message}");
        return 1;
    }
    finally
    {
        try { if (Directory.Exists(tmpDir)) Directory.Delete(tmpDir, recursive: true); } catch { }
    }

    return 0;
});

// ── start command ──
var startCommand = new Command("start", "Start the worker service");
var startJson = CreateJsonOption();
startCommand.Add(startJson);
startCommand.SetAction((ParseResult parseResult) =>
{
    return RunServiceAction(parseResult, "start", parseResult.GetValue(startJson));
});

// ── stop command ──
var stopCommand = new Command("stop", "Stop the worker service");
var stopJson = CreateJsonOption();
stopCommand.Add(stopJson);
stopCommand.SetAction((ParseResult parseResult) =>
{
    return RunServiceAction(parseResult, "stop", parseResult.GetValue(stopJson));
});

// ── restart command ──
var restartCommand = new Command("restart", "Restart the worker service");
var restartJson = CreateJsonOption();
restartCommand.Add(restartJson);
restartCommand.SetAction((ParseResult parseResult) =>
{
    return RunServiceAction(parseResult, "restart", parseResult.GetValue(restartJson));
});

rootCommand.Subcommands.Add(loginCommand);
rootCommand.Subcommands.Add(logoutCommand);
rootCommand.Subcommands.Add(statusCommand);
rootCommand.Subcommands.Add(doctorCommand);
rootCommand.Subcommands.Add(updateCommand);
rootCommand.Subcommands.Add(startCommand);
rootCommand.Subcommands.Add(stopCommand);
rootCommand.Subcommands.Add(restartCommand);

return await rootCommand.Parse(args).InvokeAsync();

public partial class Program;
