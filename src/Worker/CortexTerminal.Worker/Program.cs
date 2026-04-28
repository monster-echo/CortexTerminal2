using System.Net.Http.Json;
using CortexTerminal.Worker.Auth;
using CortexTerminal.Worker.Pty;
using CortexTerminal.Worker.Registration;
using CortexTerminal.Worker.Runtime;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

var builder = Host.CreateApplicationBuilder(args);
var gatewayUrl = Environment.GetEnvironmentVariable("CORTEX_GATEWAY_URL")
    ?? builder.Configuration["Worker:GatewayUrl"];
if (string.IsNullOrWhiteSpace(gatewayUrl))
    throw new InvalidOperationException("Gateway URL is not configured. Set CORTEX_GATEWAY_URL or Worker:GatewayUrl in appsettings.json.");
var gatewayBaseUrl = new Uri(gatewayUrl);
var workerId = Environment.GetEnvironmentVariable("CORTEX_WORKER_ID")
    ?? builder.Configuration["Worker:WorkerId"]
    ?? $"worker-{Environment.MachineName}".ToLowerInvariant();
var installDir = AppContext.BaseDirectory;

// Parse CLI args for subcommands
var command = args.FirstOrDefault(arg => !arg.StartsWith("--"));

if (command == "login")
{
    var loginTokenStore = new FileWorkerTokenStore(installDir);
    using var httpClient = new HttpClient { BaseAddress = gatewayBaseUrl };
    var loginService = new DeviceFlowLoginService(httpClient, loginTokenStore);
    await loginService.LoginAsync(CancellationToken.None);
    return;
}

// Normal worker mode
var tokenStore = new FileWorkerTokenStore(installDir);
var savedToken = await tokenStore.GetAccessTokenAsync(CancellationToken.None);

if (string.IsNullOrWhiteSpace(savedToken))
{
    Console.Error.WriteLine("Worker is not authenticated. Run 'cortex login' first.");
    Console.Error.WriteLine($"  Gateway: {gatewayUrl}");
    return;
}

// Token refresh: hold the current token in a volatile field so the HubConnection can pick up refreshed tokens
var currentToken = savedToken;

builder.Services.AddSingleton<IPtyHost, UnixPtyHost>();
builder.Services.AddSingleton<IWorkerGatewayClient>(_ =>
{
    var connection = new HubConnectionBuilder()
        .WithUrl(new Uri(gatewayBaseUrl, "/hubs/worker"), options =>
        {
            options.AccessTokenProvider = () => Task.FromResult<string?>(currentToken);
        })
        .AddMessagePackProtocol()
        .WithAutomaticReconnect()
        .Build();

    return new WorkerGatewayClient(connection);
});

// Background service that refreshes the token every 24 hours
builder.Services.AddSingleton(_ => new HttpClient { BaseAddress = gatewayBaseUrl });
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

await builder.Build().RunAsync();

public partial class Program;
