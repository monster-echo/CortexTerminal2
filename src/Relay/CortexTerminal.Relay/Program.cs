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
// 隧道路由查询是相对路径（/internal/tunnels/{key}），必须给命名 client 配 BaseAddress，
// 否则每个访客请求都会以 "BaseAddress must be set" 500 收场。
var gatewayInternalUrl = builder.Configuration[$"{RelayTunnelOptions.SectionName}:GatewayInternalUrl"];
if (string.IsNullOrWhiteSpace(gatewayInternalUrl))
{
    throw new InvalidOperationException(
        "Tunnels:GatewayInternalUrl is required — the Relay resolves tunnel routes through the Gateway internal API.");
}
builder.Services.AddHttpClient("tunnel-routes", client =>
{
    client.BaseAddress = new Uri(gatewayInternalUrl, UriKind.Absolute);
});

// 上传请求体上限 = 单传输字节上限
var relayConfig = builder.Configuration
    .GetSection(RelayOptions.SectionName)
    .Get<RelayOptions>() ?? new RelayOptions();
builder.WebHost.ConfigureKestrel(o => o.Limits.MaxRequestBodySize = relayConfig.MaxTransferBytes);

// 传输端点 CORS：签名 token 即凭据，任意来源均可直传（Web 端预检/直传必需）。
builder.Services.AddCors(options => options.AddDefaultPolicy(policy =>
    policy.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader()));

var app = builder.Build();

// 传输端点的授权完全依赖 URL 里的签名 token（无 cookie/凭据），
// 浏览器客户端（flutter web）跨域直传必须放行任意来源；预检 OPTIONS 在此终结。
app.UseCors();

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
