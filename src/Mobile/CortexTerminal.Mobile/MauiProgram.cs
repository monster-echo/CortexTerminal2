using CortexTerminal.Mobile.Bridge;
using CortexTerminal.Mobile.Services.Api;
using CortexTerminal.Mobile.Services.Auth;
using CortexTerminal.Mobile.Services.Terminal;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using System.Text.Json;
#if IOS
using Microsoft.Maui.Handlers;
#endif

namespace CortexTerminal.Mobile;

public static class MauiProgram
{
	public static MauiApp CreateMauiApp()
	{
		var builder = MauiApp.CreateBuilder();
		builder.UseMauiApp<App>();

#if IOS
		// Use custom handler that disables WKWebView's automatic
		// safe area content inset adjustment (causes blank space at bottom).
		builder.ConfigureMauiHandlers(handlers =>
		{
			handlers.AddHandler<HybridWebView, FullScreenHybridWebViewHandler>();
		});
#endif

		// Gateway URL
		builder.Services.AddSingleton(_ => GetGatewayBaseUri());
		builder.Services.AddSingleton(services => new HttpClient
		{
			BaseAddress = services.GetRequiredService<Uri>()
		});

		// Auth
		builder.Services.AddSingleton<ITokenStore, SecureTokenStore>();

		// SignalR HubConnection
		builder.Services.AddSingleton<Func<HubConnection>>(services =>
		{
			var gatewayBaseUri = services.GetRequiredService<Uri>();
			var authService = services.GetRequiredService<AuthService>();
			return () => new HubConnectionBuilder()
				.WithUrl(new Uri(gatewayBaseUri, "/hubs/terminal"), options =>
				{
					options.AccessTokenProvider = () => Task.FromResult<string?>(authService.GetCurrentToken() ?? "");
				})
				.WithAutomaticReconnect()
				.Build();
		});
		builder.Services.AddSingleton(services => services.GetRequiredService<Func<HubConnection>>()());

		// API & Services
		builder.Services.AddSingleton<RestApiService>();
		builder.Services.AddSingleton<TerminalGatewayClient>();
		builder.Services.AddSingleton<AuthService>();
		builder.Services.AddSingleton<OAuthService>();
		builder.Services.AddSingleton<WebBridge>();
		builder.Services.AddSingleton<TerminalChunkBuffer>();
		builder.Services.AddSingleton<TerminalSignalRService>();
		builder.Services.AddSingleton<MainPage>();
		builder.Services.AddSingleton<AppShell>();

#if DEBUG
		builder.Services.AddHybridWebViewDeveloperTools();
		builder.Logging.AddDebug();
#endif

		var app = builder.Build();

		// Wire up bridge handlers
		var bridge = app.Services.GetRequiredService<WebBridge>();
		var restApi = app.Services.GetRequiredService<RestApiService>();
		var authService = app.Services.GetRequiredService<AuthService>();
		var oauthService = app.Services.GetRequiredService<OAuthService>();
		var signalRService = app.Services.GetRequiredService<TerminalSignalRService>();

		// Auth handlers
		bridge.RegisterHandler("auth", "dev.login", (msg) => authService.HandleAsync(msg, default));
		bridge.RegisterHandler("auth", "getSession", (msg) => authService.HandleAsync(msg, default));
		bridge.RegisterHandler("auth", "logout", (msg) => authService.HandleAsync(msg, default));
		bridge.RegisterHandler("auth", "oauth.start", (msg) => oauthService.HandleAsync(msg, default));
		bridge.RegisterHandler("auth", "phone.sendCode", (msg) => authService.HandleAsync(msg, default));
		bridge.RegisterHandler("auth", "phone.verifyCode", (msg) => authService.HandleAsync(msg, default));

		// REST handlers - generic proxy
		bridge.RegisterHandler("rest", "*", async (msg) =>
		{
			try
			{
				var method = msg.Payload?.TryGetProperty("method", out var methodProp) == true
					? methodProp.GetString() ?? "GET" : "GET";
				var path = msg.Payload?.TryGetProperty("path", out var pathProp) == true
					? pathProp.GetString() ?? "" : "";
				var body = msg.Payload?.TryGetProperty("body", out var bodyProp) == true
					? (JsonElement?)bodyProp : null;
				var result = await restApi.SendAsync(method, path, body, default);
				return new BridgeResponse { Ok = true, Payload = result };
			}
			catch (Exception ex)
			{
				return new BridgeResponse { Ok = false, Error = ex.Message };
			}
		});

		// SignalR handlers
		bridge.RegisterHandler("signalr", "*", (msg) => signalRService.HandleBridgeRequestAsync(msg, default));

		return app;
	}

	private static Uri GetGatewayBaseUri()
	{
		var configured = Preferences.Default.Get("GatewayUrl", "");
		if (!string.IsNullOrEmpty(configured)) return new Uri(configured);

		return new Uri("https://gateway.ct.rwecho.top");
	}
}
