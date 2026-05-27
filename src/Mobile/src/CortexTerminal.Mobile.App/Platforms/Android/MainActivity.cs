using Android.App;
using Android.Content;
using Android.Content.PM;
using Android.OS;
using AndroidX.Core.View;
using CortexTerminal.Mobile.App.Services.Auth;
using Microsoft.Extensions.DependencyInjection;

namespace CortexTerminal.Mobile.App;

[Activity(Theme = "@style/Maui.SplashTheme", MainLauncher = true, LaunchMode = LaunchMode.SingleTop, ConfigurationChanges = ConfigChanges.ScreenSize | ConfigChanges.Orientation | ConfigChanges.UiMode | ConfigChanges.ScreenLayout | ConfigChanges.SmallestScreenSize | ConfigChanges.Density, WindowSoftInputMode = Android.Views.SoftInput.AdjustResize)]
public class MainActivity : MauiAppCompatActivity
{
    protected override void OnCreate(Bundle? savedInstanceState)
    {
        base.OnCreate(savedInstanceState);

        // Prevent white flash on navigation bar during dark mode startup.
        if (Window is not null)
        {
            var isDark = (Resources?.Configuration?.UiMode & Android.Content.Res.UiMode.NightMask) == Android.Content.Res.UiMode.NightYes;

#pragma warning disable CA1422
            if (Build.VERSION.SdkInt >= BuildVersionCodes.VanillaIceCream)
            {
                Window.SetNavigationBarColor(Android.Graphics.Color.Transparent);
                Window.SetStatusBarColor(Android.Graphics.Color.Transparent);
            }
            else
            {
                Window.SetNavigationBarColor(Android.Graphics.Color.ParseColor(isDark ? "#08080A" : "#ffffff"));
                Window.SetStatusBarColor(Android.Graphics.Color.ParseColor("#08080A"));
            }
#pragma warning restore CA1422

            var controller = WindowCompat.GetInsetsController(Window, Window.DecorView);
            if (controller is not null)
            {
                controller.AppearanceLightNavigationBars = !isDark;
                controller.AppearanceLightStatusBars = false;
            }
        }
    }

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
