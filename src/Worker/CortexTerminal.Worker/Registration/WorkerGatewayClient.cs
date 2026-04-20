using Microsoft.AspNetCore.SignalR.Client;

namespace CortexTerminal.Worker.Registration;

public sealed class WorkerGatewayClient(HubConnection connection)
{
    public Task RegisterAsync(string workerId, CancellationToken cancellationToken)
        => connection.InvokeAsync("RegisterWorker", workerId, cancellationToken);
}
