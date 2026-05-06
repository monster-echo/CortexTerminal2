using CortexTerminal.Mobile.Services.Auth;
using Foundation;
using Microsoft.Extensions.DependencyInjection;
using UIKit;

namespace CortexTerminal.Mobile;

[Register("AppDelegate")]
public class AppDelegate : MauiUIApplicationDelegate
{
	protected override MauiApp CreateMauiApp() => MauiProgram.CreateMauiApp();

	public override bool OpenUrl(UIApplication application, NSUrl url, NSDictionary options)
	{
		if (url.Scheme == "cortexterminal")
		{
			var uri = new Uri(url.AbsoluteString!);
			_ = HandleDeepLinkAsync(uri);
			return true;
		}
		return base.OpenUrl(application, url, options);
	}

	private async Task HandleDeepLinkAsync(Uri uri)
	{
		try
		{
			var services = Microsoft.Maui.Controls.Application.Current?.Handler?.MauiContext?.Services;
			var oauthService = services?.GetService<OAuthService>();
			if (oauthService is not null)
			{
				await oauthService.HandleDeepLinkAsync(uri, default);
			}
		}
		catch (Exception ex)
		{
			System.Diagnostics.Debug.WriteLine($"[AppDelegate] Deep link error: {ex.Message}");
		}
	}
}
