using System.Net.Http.Json;
using CortexTerminal.Contracts.Sessions;

namespace CortexTerminal.Mobile.Services.Terminal;

public sealed class TerminalGatewayClient(HttpClient httpClient)
{
    public async Task<CreateSessionResponse?> CreateSessionAsync(int columns, int rows, CancellationToken cancellationToken)
    {
        using var response = await httpClient.PostAsJsonAsync("/api/sessions", new CreateSessionRequest("shell", columns, rows), cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<CreateSessionResponse>(cancellationToken: cancellationToken);
    }
}
