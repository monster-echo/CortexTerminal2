using CortexTerminal.Contracts.Streaming;
using CortexTerminal.Relay;
using CortexTerminal.Relay.Transfers;
using CortexTerminal.Relay.Tunnels;
using CortexTerminal.Relay.Workers;
using Microsoft.Extensions.Options;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<RelayOptions>(builder.Configuration.GetSection(RelayOptions.SectionName));
builder.Services.Configure<RelayTunnelOptions>(builder.Configuration.GetSection(RelayTunnelOptions.SectionName));
builder.Services.AddSingleton<TransferPairingRegistry>();
builder.Services.AddHostedService<TransferSweeper>();
builder.Services.AddSingleton<WorkerRelayRegistry>();
builder.Services.AddSingleton<TunnelRouteResolver>();
builder.Services.AddHttpClient("tunnel-routes");

// 上传请求体上限 = 单传输字节上限
var relayConfig = builder.Configuration
    .GetSection(RelayOptions.SectionName)
    .Get<RelayOptions>() ?? new RelayOptions();
builder.WebHost.ConfigureKestrel(o => o.Limits.MaxRequestBodySize = relayConfig.MaxTransferBytes);

var app = builder.Build();

app.UseWebSockets(new WebSocketOptions { KeepAliveInterval = TimeSpan.FromSeconds(30) });
app.UseMiddleware<TunnelEntryMiddleware>();

app.MapGet("/healthz", () => Results.Ok(new { status = "ok" }));

// ── Worker 持久 WS（隧道数据面 + 传输预备连接的承载协议无关）────────
app.MapGet("/worker", async (
    HttpContext context,
    WorkerRelayRegistry workers,
    IOptions<RelayOptions> options) =>
{
    var opts = options.Value;
    var workerId = context.Request.Query["workerId"].FirstOrDefault() ?? string.Empty;
    var token = context.Request.Query["token"].FirstOrDefault() ?? string.Empty;
    if (workerId.Length == 0 || token.Length == 0
        || !RelayToken.TryValidate(opts.SharedSecret, token, RelayToken.AudienceWorkerRelay, workerId, out _))
    {
        return Results.Unauthorized();
    }
    if (!context.WebSockets.IsWebSocketRequest)
    {
        return Results.BadRequest(new { error = "websocket_required" });
    }

    var socket = await context.WebSockets.AcceptWebSocketAsync();
    var connection = new WorkerRelayConnection(workerId, socket);
    workers.Register(connection);
    try
    {
        await connection.RunAsync(context.RequestAborted);
    }
    finally
    {
        workers.Unregister(workerId, connection);
    }
    return Results.Empty;
});

TransferEndpoints.Map(app);

app.Run();
