using System.Net;
using System.Net.NetworkInformation;
using System.Net.WebSockets;
using CortexTerminal.Worker.RemoteFiles;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Tunnels;

/// <summary>
/// LAN/公网直连传输监听器（P2P 端点协商的本地端点）：绑定 0.0.0.0:&lt;port&gt;，暴露与 Relay
/// 相同契约的 PUT/GET /transfer/{tid}?token=...。手机与 Worker 同网段（或公网可达）时直连
/// 本监听器，流量不经 Relay。token 由 Gateway 在 Prepare RPC 中下发，常量时间比对。
/// </summary>
public sealed class LocalTransferListener : BackgroundService
{
    private readonly RelayTransferService _transfers;
    private readonly int _listenPort;
    private readonly ILogger<LocalTransferListener> _logger;
    private readonly TaskCompletionSource _ready =
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    public LocalTransferListener(
        RelayTransferService transfers,
        int listenPort,
        string? publicBaseUrl,
        ILogger<LocalTransferListener> logger)
    {
        _transfers = transfers;
        _listenPort = listenPort;
        PublicBaseUrl = string.IsNullOrWhiteSpace(publicBaseUrl) ? null : publicBaseUrl.TrimEnd('/');
        _logger = logger;
    }

    /// <summary>本机各网卡的 LAN 传输基地址（如 http://192.168.1.10:47631）。绑定完成后可用。</summary>
    public IReadOnlyList<string> LanBaseUrls { get; private set; } = Array.Empty<string>();

    /// <summary>实际绑定的端口（listenPort=0 时为系统分配的临时端口）。绑定完成后可用。</summary>
    public int BoundPort { get; private set; }

    /// <summary>可选的公网直连基地址（用户为该 Worker 配置的域名/端口）。</summary>
    public string? PublicBaseUrl { get; }

    /// <summary>端口绑定完成信号（成功或失败）。</summary>
    public Task Ready => _ready.Task;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            var builder = WebApplication.CreateBuilder();
            builder.Logging.ClearProviders();
            builder.Logging.AddProvider(new ForwardingLoggerProvider(_logger));
            builder.WebHost.UseKestrel(serverOptions =>
            {
                serverOptions.Listen(IPAddress.Any, _listenPort);
            });

            var app = builder.Build();
            app.MapPut("/transfer/{transferId}", async (string transferId, HttpContext ctx) =>
            {
                var token = ReadToken(ctx);
                var outcome = await _transfers.HandleLocalUploadAsync(
                    transferId, token, ctx.Request.Body, ctx.RequestAborted);
                if (outcome.Success)
                {
                    return Results.Json(new { success = true });
                }
                return Results.Json(
                    new { error = outcome.Code ?? "transfer_failed", message = outcome.Message },
                    statusCode: outcome.Status);
            });

            app.MapGet("/transfer/{transferId}", async Task (string transferId, HttpContext ctx) =>
            {
                var token = ReadToken(ctx);
                var (outcome, handle) = await _transfers.HandleLocalDownloadAsync(transferId, token, ctx.RequestAborted);
                if (!outcome.Success || handle is null)
                {
                    ctx.Response.StatusCode = outcome.Status;
                    ctx.Response.ContentType = "application/json";
                    await ctx.Response.WriteAsync(
                        System.Text.Json.JsonSerializer.Serialize(
                            new { error = outcome.Code ?? "transfer_failed", message = outcome.Message }));
                    return;
                }

                ctx.Response.StatusCode = StatusCodes.Status200OK;
                ctx.Response.ContentType = "application/octet-stream";
                ctx.Response.ContentLength = handle.SizeBytes;
                ctx.Response.Headers.Append("Content-Disposition",
                    $"attachment; filename=\"{handle.Filename}\"");
                await using var stream = File.OpenRead(handle.FilePath);
                await stream.CopyToAsync(ctx.Response.Body, ctx.RequestAborted);
            });

            await app.StartAsync(stoppingToken);

            var port = ResolveBoundPort(app);
            BoundPort = port;
            LanBaseUrls = EnumerateLanIpv4Addresses()
                .Select(ip => $"http://{ip}:{port}")
                .ToArray();
            _ready.TrySetResult();
            _logger.LogInformation(
                "Local transfer listener ready on port {Port}; LAN endpoints: {Endpoints}.",
                port, string.Join(", ", LanBaseUrls));

            await app.WaitForShutdownAsync(stoppingToken);
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            _ready.TrySetCanceled();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Local transfer listener failed to start.");
            _ready.TrySetException(ex);
        }
    }

    private static string ReadToken(HttpContext ctx)
        => ctx.Request.Query["token"].FirstOrDefault()
           ?? ctx.Request.Headers["X-Corterm-Transfer-Token"].FirstOrDefault()
           ?? string.Empty;

    private static int ResolveBoundPort(WebApplication app)
    {
        var addresses = app.Services
            .GetRequiredService<IServer>()
            .Features
            .Get<IServerAddressesFeature>()
            ?.Addresses ?? Array.Empty<string>();
        foreach (var address in addresses)
        {
            if (Uri.TryCreate(address, UriKind.Absolute, out var uri))
            {
                return uri.Port;
            }
        }
        throw new InvalidOperationException("Kestrel did not report any bound addresses.");
    }

    /// <summary>本机所有非环回 IPv4 地址（排除链路本地 169.254.*），供手机在同网段直连。</summary>
    internal static IReadOnlyList<string> EnumerateLanIpv4Addresses()
    {
        var addresses = new List<string>();
        foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (nic.OperationalStatus != OperationalStatus.Up
                || nic.NetworkInterfaceType == NetworkInterfaceType.Loopback)
            {
                continue;
            }
            foreach (var address in nic.GetIPProperties().UnicastAddresses)
            {
                if (address.Address.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork)
                {
                    continue;
                }
                var text = address.Address.ToString();
                if (text.StartsWith("169.254.", StringComparison.Ordinal))
                {
                    continue;
                }
                addresses.Add(text);
            }
        }
        return addresses.Distinct().ToArray();
    }

    private sealed class ForwardingLoggerProvider(ILogger logger) : ILoggerProvider
    {
        public ILogger CreateLogger(string categoryName) => logger;

        public void Dispose() { }
    }
}
