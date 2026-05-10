using Android.App;
using Android.Content.PM;

namespace CortexTerminal.Mobile.App;

[Activity(
    NoHistory = true,
    Exported = true,
    LaunchMode = LaunchMode.SingleTop)]
[IntentFilter(
    [Android.Content.Intent.ActionView],
    Categories = [Android.Content.Intent.CategoryDefault, Android.Content.Intent.CategoryBrowsable],
    DataScheme = "corterm.mobile",
    DataHost = "auth")]
public sealed class WebAuthenticatorCallbackActivity : Microsoft.Maui.Authentication.WebAuthenticatorCallbackActivity
{
}
