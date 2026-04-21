using System.Net.Http.Json;
using CortexTerminal.Contracts.Sessions;
using Microsoft.AspNetCore.SignalR.Client;

namespace CortexTerminal.Mobile.Services.Terminal;

public sealed class TerminalGatewayClient(HttpClient httpClient, HubConnection hubConnection)
{
    public async Task<CreateSessionResponse?> CreateSessionAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        using var response = await httpClient.PostAsJsonAsync("/api/sessions", new CreateSessionRequest("shell", columns, rows), cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<CreateSessionResponse>(cancellationToken: cancellationToken);
    }

    public async Task DetachSessionAsync(string sessionId, CancellationToken cancellationToken)
    {
        await EnsureConnectedAsync(cancellationToken);
        await hubConnection.InvokeAsync("DetachSession", sessionId, cancellationToken);
    }

    public async Task<ReattachSessionResult> ReattachSessionAsync(string sessionId, CancellationToken cancellationToken)
    {
        await EnsureConnectedAsync(cancellationToken);
        return await hubConnection.InvokeAsync<ReattachSessionResult>("ReattachSession", new ReattachSessionRequest(sessionId), cancellationToken);
    }

    private async Task EnsureConnectedAsync(CancellationToken cancellationToken)
    {
        if (hubConnection.State == HubConnectionState.Disconnected)
        {
            await hubConnection.StartAsync(cancellationToken);
        }
    }
}
