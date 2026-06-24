using CortexTerminal.Mobile.Core.Bridge;

namespace CortexTerminal.Mobile.App.Services.Bridge;

public sealed partial class AppBridge
{
    [BridgeMethod]
    public Task<string> GetGatewayInfoAsync()
    {
        return ExecuteSafeAsync(async () =>
        {
            var info = await RequireTerminalGateway().GetGatewayInfoAsync(default);
            return new
            {
                version = info.Version,
                latestWorkerVersion = info.LatestWorkerVersion,
                latestGatewayVersion = info.LatestGatewayVersion,
            };
        });
    }

    [BridgeMethod]
    public Task<string> UpgradeTerminalWorkerAsync(string workerId)
    {
        return ExecuteSafeAsync(async () =>
        {
            var result = await RequireTerminalGateway().UpgradeWorkerAsync(workerId, default);
            return new { message = result.Message, targetVersion = result.TargetVersion };
        });
    }
}
