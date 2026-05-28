namespace CortexTerminal.Mobile.App.Services.Auth;

public sealed class UnauthorizedHandler(AuthService authService) : DelegatingHandler
{
    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var response = await base.SendAsync(request, cancellationToken);
        if (response.StatusCode == System.Net.HttpStatusCode.Unauthorized
            && authService.AccessToken != null
            && authService.AccessToken != "guest")
        {
            await authService.LogoutAsync(cancellationToken);
        }
        return response;
    }
}
