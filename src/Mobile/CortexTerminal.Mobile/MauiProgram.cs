using CortexTerminal.Mobile.Services.Terminal;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Mobile;

public static class MauiProgram
{
	public static MauiApp CreateMauiApp()
	{
		var builder = MauiApp.CreateBuilder();
		builder.UseMauiApp<App>();

		builder.Services.AddSingleton(_ => GetGatewayBaseUri());
		builder.Services.AddSingleton(services => new HttpClient
		{
			BaseAddress = services.GetRequiredService<Uri>()
		});
		builder.Services.AddSingleton<Func<HubConnection>>(services =>
		{
			var gatewayBaseUri = services.GetRequiredService<Uri>();
			return () => new HubConnectionBuilder()
				.WithUrl(new Uri(gatewayBaseUri, "/hubs/terminal"))
				.WithAutomaticReconnect()
				.Build();
		});
		builder.Services.AddSingleton(services => services.GetRequiredService<Func<HubConnection>>()());
		builder.Services.AddSingleton<TerminalGatewayClient>();

#if DEBUG
		builder.Logging.AddDebug();
#endif

		return builder.Build();
	}

	private static Uri GetGatewayBaseUri()
	{
		var host = DeviceInfo.Platform == DevicePlatform.Android ? "10.0.2.2" : "localhost";
		return new Uri($"http://{host}:5045");
	}
}
