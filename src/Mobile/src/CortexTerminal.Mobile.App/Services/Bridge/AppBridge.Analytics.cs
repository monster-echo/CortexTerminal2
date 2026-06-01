using System.Text.Json;
using CortexTerminal.Mobile.Core.Bridge;
using CortexTerminal.Mobile.Core.Diagnostics;

#if IOS || ANDROID
using Plugin.Firebase.Analytics;
#endif

namespace CortexTerminal.Mobile.App.Services.Bridge;

public sealed partial class AppBridge
{
    [BridgeMethod]
    public Task<string> TrackAnalyticsEventAsync(string eventName, Dictionary<string, object?>? parameters = null)
    {
        return ExecuteSafeVoidAsync(() =>
        {
            var safeParams = parameters?
                .Where(kvp => !string.IsNullOrWhiteSpace(kvp.Key) && kvp.Value != null)
                .ToDictionary(
                    kvp => kvp.Key,
                    kvp => kvp.Value is JsonElement je ? je.ToString() : kvp.Value?.ToString() ?? "");

#if IOS || ANDROID
            CrossFirebaseAnalytics.Current.LogEvent(eventName,
                safeParams?.ToDictionary(k => k.Key, v => (object)v.Value) ?? new());
#endif

            return Task.CompletedTask;
        });
    }

    [BridgeMethod]
    public Task<string> SetAnalyticsUserIdAsync(string userId)
    {
        return ExecuteSafeVoidAsync(() =>
        {
#if IOS || ANDROID
            CrossFirebaseAnalytics.Current.SetUserId(userId);
#endif
            return Task.CompletedTask;
        });
    }
}
