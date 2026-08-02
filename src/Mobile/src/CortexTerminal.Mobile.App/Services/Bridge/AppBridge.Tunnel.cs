using CortexTerminal.Contracts.Sessions;
using CortexTerminal.Mobile.App.Services.Terminal;
using CortexTerminal.Mobile.Core.Bridge;

namespace CortexTerminal.Mobile.App.Services.Bridge;

public sealed partial class AppBridge
{
    [BridgeMethod]
    public Task<string> CreateTunnelAsync(string sessionId, int port)
    {
        return ExecuteSafeAsync(async () =>
        {
            var terminal = RequireTerminalGateway();
            var tunnel = await terminal.CreateTunnelAsync(sessionId, port, default);
            return new
            {
                tunnel.TunnelId,
                tunnel.TunnelKey,
                tunnel.Port,
                tunnel.SessionId,
                tunnel.WorkerId,
                tunnel.Url,
                tunnel.Secret,
                tunnel.ExpiresAtUtc,
                tunnel.CreatedAtUtc,
            };
        });
    }

    [BridgeMethod]
    public Task<string> ListTunnelsAsync(string sessionId)
    {
        return ExecuteSafeAsync(async () =>
        {
            var terminal = RequireTerminalGateway();
            var tunnels = await terminal.ListTunnelsAsync(sessionId, default);
            return tunnels.Select(t => new
            {
                t.TunnelId,
                t.TunnelKey,
                t.Port,
                t.SessionId,
                t.WorkerId,
                t.Url,
                t.Secret,
                t.ExpiresAtUtc,
                t.CreatedAtUtc,
            }).ToList();
        });
    }

    [BridgeMethod]
    public Task<string> RevokeTunnelAsync(string tunnelId)
    {
        return ExecuteSafeVoidAsync(async () =>
        {
            var terminal = RequireTerminalGateway();
            await terminal.RevokeTunnelAsync(tunnelId, default);
        });
    }
}
