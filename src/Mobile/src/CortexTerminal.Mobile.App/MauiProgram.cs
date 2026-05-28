using Microsoft.Extensions.Logging;
using CommunityToolkit.Maui;
using CortexTerminal.Mobile.App.Services.Auth;
using CortexTerminal.Mobile.App.Services.Bridge;
using CortexTerminal.Mobile.App.Services.Terminal;
using Microsoft.Extensions.Configuration;

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
		builder.Configuration.AddJsonFile("appsettings.json", optional: true, reloadOnChange: false);
		builder.Services.AddSingleton(sp =>
		{
			var gatewayBaseUri = sp.GetRequiredService<IConfiguration>()["App:GatewayBaseUri"];
			return new Uri(string.IsNullOrWhiteSpace(gatewayBaseUri)
				? "https://gateway.ct.rwecho.top"
				: gatewayBaseUri);
		});
		// Auth services
		builder.Services.AddSingleton<ITokenStore, SecureTokenStore>();
		builder.Services.AddSingleton(sp =>
		{
			var gatewayBaseUri = sp.GetRequiredService<Uri>();
			var authService = new AuthService(
				sp.GetRequiredService<ITokenStore>(),
				new HttpClient(CreateGatewayHandler()) { BaseAddress = gatewayBaseUri, Timeout = TimeSpan.FromSeconds(30) });
			return authService;
		});
		builder.Services.AddSingleton(sp =>
		{
			var gatewayBaseUri = sp.GetRequiredService<Uri>();
			var authService = sp.GetRequiredService<AuthService>();
			var handler = new UnauthorizedHandler(authService)
			{
				InnerHandler = CreateGatewayHandler()
			};
			var httpClient = new HttpClient(handler) { BaseAddress = gatewayBaseUri, Timeout = TimeSpan.FromSeconds(30) };
			return new TerminalGatewayService(
				gatewayBaseUri,
				authService,
				httpClient,
				sp.GetRequiredService<ILogger<TerminalGatewayService>>());
		});
		builder.Services.AddSingleton(sp =>
		{
			return new OAuthService(sp.GetRequiredService<Uri>(), sp.GetRequiredService<AuthService>());
		});
		builder.Services.AddSingleton<AppBridge>(sp =>
		{
			var logger = sp.GetRequiredService<ILogger<AppBridge>>();
			var bridge = new AppBridge(logger);
			var authService = sp.GetRequiredService<AuthService>();
			var oauthService = sp.GetRequiredService<OAuthService>();
			var terminalGateway = sp.GetRequiredService<TerminalGatewayService>();
			bridge.SetAuthServices(authService, oauthService);
			bridge.SetTerminalGateway(terminalGateway);
			return bridge;
		});

#if DEBUG
		builder.Services.AddHybridWebViewDeveloperTools();
		builder.Logging.AddDebug();
#endif

		return builder.Build();
	}

	internal static HttpMessageHandler CreateGatewayHandler()
	{
#if IOS || MACCATALYST
		return new NSUrlSessionHandler();
#else
		return new HttpClientHandler();
#endif
	}
}
