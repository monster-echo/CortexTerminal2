using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Worker.Auth;

public sealed class TokenRefreshService : BackgroundService
{
    private readonly DeviceFlowLoginService _loginService;
    private readonly IWorkerTokenStore _tokenStore;
    private readonly Func<string> _getCurrentToken;
    private readonly Action<string> _setCurrentToken;
    private readonly ILogger<TokenRefreshService> _logger;

    public TokenRefreshService(
        HttpClient httpClient,
        IWorkerTokenStore tokenStore,
        Func<string> getCurrentToken,
        Action<string> setCurrentToken,
        ILogger<TokenRefreshService> logger)
    {
        _loginService = new DeviceFlowLoginService(httpClient, tokenStore);
        _tokenStore = tokenStore;
        _getCurrentToken = getCurrentToken;
        _setCurrentToken = setCurrentToken;
        _logger = logger;
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
                _logger.LogInformation("Refreshing authentication token...");
                var refreshed = await _loginService.RefreshTokenAsync(_getCurrentToken(), stoppingToken);
                if (refreshed is not null)
                {
                    _setCurrentToken(refreshed);
                    _logger.LogInformation("Token refreshed successfully.");
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Token refresh failed; will retry next cycle.");
            }
        }
    }
}
