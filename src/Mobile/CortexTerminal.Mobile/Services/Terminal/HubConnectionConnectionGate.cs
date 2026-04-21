using Microsoft.AspNetCore.SignalR.Client;

namespace CortexTerminal.Mobile.Services.Terminal;

internal static class HubConnectionConnectionGate
{
    private static readonly TimeSpan PollInterval = TimeSpan.FromMilliseconds(50);

    public static async Task EnsureConnectedAsync(
        Func<HubConnectionState> getState,
        Func<CancellationToken, Task> startAsync,
        CancellationToken cancellationToken)
    {
        while (true)
        {
            var state = getState();

            if (state == HubConnectionState.Connected)
            {
                return;
            }

            if (state == HubConnectionState.Disconnected)
            {
                await startAsync(cancellationToken);
                continue;
            }

            await Task.Delay(PollInterval, cancellationToken);
        }
    }
}
