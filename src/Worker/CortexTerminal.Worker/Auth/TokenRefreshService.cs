using Microsoft.Extensions.Hosting;

namespace CortexTerminal.Worker.Auth;

public sealed class TokenRefreshService : BackgroundService
{
    private readonly DeviceFlowLoginService _loginService;
    private readonly IWorkerTokenStore _tokenStore;
    private readonly Func<string> _getCurrentToken;
    private readonly Action<string> _setCurrentToken;

    public TokenRefreshService(
        HttpClient httpClient,
        IWorkerTokenStore tokenStore,
        Func<string> getCurrentToken,
        Action<string> setCurrentToken)
    {
        _loginService = new DeviceFlowLoginService(httpClient, tokenStore);
        _tokenStore = tokenStore;
        _getCurrentToken = getCurrentToken;
        _setCurrentToken = setCurrentToken;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromHours(24), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }

            try
            {
                var refreshed = await _loginService.RefreshTokenAsync(_getCurrentToken(), stoppingToken);
                if (refreshed is not null)
                {
                    _setCurrentToken(refreshed);
                }
            }
            catch
            {
                // Refresh failed; will retry next cycle
            }
        }
    }
}
