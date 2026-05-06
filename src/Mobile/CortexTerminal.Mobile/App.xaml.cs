using CortexTerminal.Mobile.Services.Auth;
using CortexTerminal.Mobile.Services.Terminal;
using Microsoft.Extensions.DependencyInjection;

namespace CortexTerminal.Mobile;

public partial class App : Application
{
	private readonly AppShell _appShell;

	public App(AppShell appShell)
	{
		InitializeComponent();
		_appShell = appShell;
	}

	protected override Window CreateWindow(IActivationState? activationState)
	{
		return new Window(_appShell);
	}

	protected override void OnSleep()
	{
		base.OnSleep();
		TryGetChunkBuffer()?.StartBuffering();
	}

	protected override async void OnResume()
	{
		base.OnResume();
		var buffer = TryGetChunkBuffer();
		if (buffer is not null)
		{
			await buffer.StopBufferingAndFlushAsync();
		}
	}

	protected override async void OnAppLinkRequestReceived(Uri uri)
	{
		base.OnAppLinkRequestReceived(uri);

		if (string.Equals(uri.Scheme, "cortexterminal", StringComparison.OrdinalIgnoreCase))
		{
			try
			{
				var oauthService = Current?.Handler?.MauiContext?.Services?.GetService<OAuthService>();
				if (oauthService is not null)
				{
					await oauthService.HandleDeepLinkAsync(uri, default);
				}
			}
			catch (Exception ex)
			{
				System.Diagnostics.Debug.WriteLine($"[App] Deep link error: {ex.Message}");
			}
		}
	}

	private TerminalChunkBuffer? TryGetChunkBuffer()
	{
		try
		{
			var handler = Current?.Handler?.MauiContext?.Services;
			return handler?.GetService<TerminalChunkBuffer>();
		}
		catch
		{
			return null;
		}
	}
}
