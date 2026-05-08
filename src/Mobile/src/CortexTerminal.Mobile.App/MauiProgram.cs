using Microsoft.Extensions.Logging;
using CommunityToolkit.Maui;
using CortexTerminal.Mobile.App.Services.Auth;
using CortexTerminal.Mobile.App.Services.Bridge;

namespace CortexTerminal.Mobile.App;

public static class MauiProgram
{
	public static MauiApp CreateMauiApp()
	{
		var builder = MauiApp.CreateBuilder();
		builder
			.UseMauiApp<App>()
			.UseMauiCommunityToolkit()
			.ConfigureFonts(fonts =>
			{
				fonts.AddFont("OpenSans-Regular.ttf", "OpenSansRegular");
				fonts.AddFont("OpenSans-Semibold.ttf", "OpenSansSemibold");
			});

		builder.Services.AddSingleton<AppShell>();
		builder.Services.AddSingleton<MainPage>();
		// Auth services
		builder.Services.AddSingleton<ITokenStore, SecureTokenStore>();
		builder.Services.AddSingleton(sp =>
		{
			var httpClient = new HttpClient { BaseAddress = new Uri("https://gateway.ct.rwecho.top") };
			return new AuthService(sp.GetRequiredService<ITokenStore>(), httpClient);
		});
		builder.Services.AddSingleton(sp =>
		{
			return new OAuthService(new Uri("https://gateway.ct.rwecho.top"), sp.GetRequiredService<AuthService>());
		});
		builder.Services.AddSingleton<AppBridge>(sp =>
		{
			var logger = sp.GetRequiredService<ILogger<AppBridge>>();
			var bridge = new AppBridge(logger);
			var authService = sp.GetRequiredService<AuthService>();
			var oauthService = sp.GetRequiredService<OAuthService>();
			bridge.SetAuthServices(authService, oauthService);
			return bridge;
		});

#if DEBUG
		builder.Services.AddHybridWebViewDeveloperTools();
		builder.Logging.AddDebug();
#endif

		return builder.Build();
	}
}
