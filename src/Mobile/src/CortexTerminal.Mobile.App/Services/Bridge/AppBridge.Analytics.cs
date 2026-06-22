using System.Text.Json;
using CortexTerminal.Mobile.Core.Bridge;
using CortexTerminal.Mobile.Core.Diagnostics;

#if ANDROID
using Android.OS;
using Firebase.Analytics;
#elif IOS
using Foundation;
using Firebase.Analytics;
#endif

namespace CortexTerminal.Mobile.App.Services.Bridge;

public sealed partial class AppBridge
{
    private static Dictionary<string, string> NormalizeParameters(Dictionary<string, object?>? parameters)
    {
        if (parameters is null || parameters.Count == 0) return new();

        var result = new Dictionary<string, string>();
        foreach (var kvp in parameters)
        {
            if (string.IsNullOrWhiteSpace(kvp.Key) || kvp.Value is null) continue;
            var value = kvp.Value is JsonElement je ? je.ToString() : kvp.Value.ToString();
            result[kvp.Key] = value ?? string.Empty;
        }
        return result;
    }

#if ANDROID
    private static Bundle ToBundle(IReadOnlyDictionary<string, string> parameters)
    {
        var bundle = new Bundle();
        foreach (var kvp in parameters)
        {
            bundle.PutString(kvp.Key, kvp.Value);
        }
        return bundle;
    }
#elif IOS
    private static NSDictionary<NSString, NSObject>? ToNSDictionary(IReadOnlyDictionary<string, string> parameters)
    {
        if (parameters.Count == 0) return null;

        var keys = new NSObject[parameters.Count];
        var values = new NSObject[parameters.Count];
        var i = 0;
        foreach (var kvp in parameters)
        {
            keys[i] = new NSString(kvp.Key);
            values[i] = new NSString(kvp.Value);
            i++;
        }
        return NSDictionary<NSString, NSObject>.FromObjectsAndKeys(values, keys);
    }
#endif

    [BridgeMethod]
    public Task<string> TrackAnalyticsEventAsync(string eventName, Dictionary<string, object?>? parameters = null)
    {
        return ExecuteSafeVoidAsync(() =>
        {
            var safeParams = NormalizeParameters(parameters);

#if ANDROID
            FirebaseAnalytics.GetInstance(Android.App.Application.Context).LogEvent(eventName, ToBundle(safeParams));
#elif IOS
            Analytics.LogEvent(eventName, ToNSDictionary(safeParams));
#endif
            return Task.CompletedTask;
        });
    }

    [BridgeMethod]
    public Task<string> SetAnalyticsUserIdAsync(string userId)
    {
        return ExecuteSafeVoidAsync(() =>
        {
            // Firebase rejects empty string: "User ID must be non-empty or null". Normalize to null.
            var normalized = string.IsNullOrEmpty(userId) ? null : userId;

#if ANDROID
            FirebaseAnalytics.GetInstance(Android.App.Application.Context).SetUserId(normalized);
#elif IOS
            Analytics.SetUserId(normalized);
#endif
            return Task.CompletedTask;
        });
    }

    [BridgeMethod]
    public Task<string> SetAnalyticsUserPropertyAsync(string name, string value)
    {
        return ExecuteSafeVoidAsync(() =>
        {
            if (string.IsNullOrWhiteSpace(name))
            {
                throw new ArgumentException("User property name must not be empty.", nameof(name));
            }

#if ANDROID
            FirebaseAnalytics.GetInstance(Android.App.Application.Context).SetUserProperty(name, value);
#elif IOS
            Analytics.SetUserProperty(value, name);
#endif
            return Task.CompletedTask;
        });
    }
}
