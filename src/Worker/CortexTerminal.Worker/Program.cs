using CortexTerminal.Worker.Pty;
using CortexTerminal.Worker.Registration;
using CortexTerminal.Worker.Runtime;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

var builder = Host.CreateApplicationBuilder(args);
var gatewayBaseUrl = new Uri(Environment.GetEnvironmentVariable("CORTEX_GATEWAY_URL") ?? "http://localhost:5045");
var workerId = Environment.GetEnvironmentVariable("CORTEX_WORKER_ID")
    ?? $"worker-{Environment.MachineName}".ToLowerInvariant();

builder.Services.AddSingleton<IPtyHost, UnixPtyHost>();
builder.Services.AddSingleton<IWorkerGatewayClient>(_ =>
{
    var connection = new HubConnectionBuilder()
        .WithUrl(new Uri(gatewayBaseUrl, "/hubs/worker"))
        .AddMessagePackProtocol()
        .WithAutomaticReconnect()
        .Build();

    return new WorkerGatewayClient(connection);
});
builder.Services.AddHostedService(services => new WorkerRuntimeHost(
    workerId,
    services.GetRequiredService<IWorkerGatewayClient>(),
    services.GetRequiredService<IPtyHost>(),
    services.GetRequiredService<ILoggerFactory>()));

await builder.Build().RunAsync();

public partial class Program;
