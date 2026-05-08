using CortexTerminal.Mobile.App.Services.Auth;
using Microsoft.Extensions.DependencyInjection;

namespace CortexTerminal.Mobile.App;

public partial class App : Application
{
	private readonly AppShell _appShell;

	public static event Action? AppResumed;
	public static event Action? AppSlept;
	public static DateTimeOffset? LastSleepTime { get; private set; }

	public App(AppShell appShell)
	{
		InitializeComponent();
		_appShell = appShell;
	}

	protected override void OnSleep()
	{
		LastSleepTime = DateTimeOffset.UtcNow;
		AppSlept?.Invoke();
		base.OnSleep();
	}

	protected override void OnResume()
	{
		AppResumed?.Invoke();
		base.OnResume();
	}

	protected override Window CreateWindow(IActivationState? activationState)
	{
		return new Window(_appShell);
	}

	protected override async void OnAppLinkRequestReceived(Uri uri)
	{
		base.OnAppLinkRequestReceived(uri);

		if (string.Equals(uri.Scheme, "cortexterminal.mobile", StringComparison.OrdinalIgnoreCase))
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
}