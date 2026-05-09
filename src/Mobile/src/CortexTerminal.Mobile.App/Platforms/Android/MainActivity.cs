using Android.App;
using Android.Content;
using Android.Content.PM;
using Android.OS;
using CortexTerminal.Mobile.App.Services.Auth;
using Microsoft.Extensions.DependencyInjection;

namespace CortexTerminal.Mobile.App;

[Activity(Theme = "@style/Maui.SplashTheme", MainLauncher = true, LaunchMode = LaunchMode.SingleTop, ConfigurationChanges = ConfigChanges.ScreenSize | ConfigChanges.Orientation | ConfigChanges.UiMode | ConfigChanges.ScreenLayout | ConfigChanges.SmallestScreenSize | ConfigChanges.Density, WindowSoftInputMode = Android.Views.SoftInput.AdjustResize)]
public class MainActivity : MauiAppCompatActivity
{
    protected override void OnNewIntent(Intent? intent)
    {
        base.OnNewIntent(intent);

        if (intent?.Action == Intent.ActionView && intent.Data is not null)
        {
            var uri = new Uri(intent.Data.ToString()!);
            _ = HandleDeepLinkAsync(uri);
        }
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
            System.Diagnostics.Debug.WriteLine($"[MainActivity] Deep link error: {ex.Message}");
        }
    }
}
