using Microsoft.Extensions.Logging;
using CommunityToolkit.Maui;
using CortexTerminal.Mobile.App.Services.Auth;
using CortexTerminal.Mobile.App.Services.Bridge;
using CortexTerminal.Mobile.App.Services.Terminal;
using CortexTerminal.Mobile.App.Services.Support;
using Microsoft.Extensions.Configuration;
using Serilog;
using CortexTerminal.Mobile.App.Services;
using System.Net.Http.Headers;

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
				? "https://corterm.rwecho.top"
				: gatewayBaseUri);
		});
		// Auth services
		builder.Services.AddSingleton<ITokenStore, SecureTokenStore>();
		builder.Services.AddSingleton(sp =>
		{
			var gatewayBaseUri = sp.GetRequiredService<Uri>();
			var authService = new AuthService(
				sp.GetRequiredService<ITokenStore>(),
				CreateGatewayHttpClient(gatewayBaseUri));
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
			var httpClient = CreateGatewayHttpClient(gatewayBaseUri, handler);
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
		builder.Services.AddSingleton(sp =>
		{
			var gatewayBaseUri = sp.GetRequiredService<Uri>();
			return new SupportService(CreateGatewayHttpClient(gatewayBaseUri), sp.GetRequiredService<AuthService>());
		});
		builder.Services.AddSingleton<AppBridge>(sp =>
		{
			var logger = sp.GetRequiredService<ILogger<AppBridge>>();
			var bridge = new AppBridge(logger);
			var authService = sp.GetRequiredService<AuthService>();
			var oauthService = sp.GetRequiredService<OAuthService>();
			var terminalGateway = sp.GetRequiredService<TerminalGatewayService>();
			var supportService = sp.GetRequiredService<SupportService>();
			bridge.SetAuthServices(authService, oauthService);
			bridge.SetTerminalGateway(terminalGateway);
			bridge.SetSupportServices(supportService);
			return bridge;
		});

#if DEBUG
		builder.Services.AddHybridWebViewDeveloperTools();
#endif

		Log.Logger = new LoggerConfiguration()
			.MinimumLevel.Debug()
			.WriteTo.Console()
			.WriteTo.File(
				Path.Combine(FileSystem.AppDataDirectory, "logs", "corterm-.txt"),
				rollingInterval: RollingInterval.Day,
				retainedFileCountLimit: 7)
			.WriteTo.FirebaseCrashlytics()
			.CreateLogger();

		builder.Logging.AddSerilog(dispose: true);

		builder.Services.AddSingleton<PushNotificationService>();

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

	internal static HttpClient CreateGatewayHttpClient(Uri baseAddress, HttpMessageHandler? innerHandler = null)
	{
		var handler = innerHandler ?? CreateGatewayHandler();
		var client = new HttpClient(handler) { BaseAddress = baseAddress, Timeout = TimeSpan.FromSeconds(30) };
		client.DefaultRequestHeaders.UserAgent.ParseAdd(BuildUserAgent());
		return client;
	}

	internal static string BuildUserAgent()
	{
		var version = "unknown";
		var platform = DeviceInfo.Current.Platform.ToString();
		var model = string.IsNullOrWhiteSpace(DeviceInfo.Current.Model) ? "unknown" : DeviceInfo.Current.Model;
		var osVersion = DeviceInfo.Current.VersionString ?? "unknown";
		try
		{
			version = AppInfo.Current.BuildString;
		}
		catch
		{
			// AppInfo may not be available in design-time / preview contexts
		}
		return $"CortexTerminal.Mobile.App/{version} ({platform}; {model}; {osVersion})";
	}
}
