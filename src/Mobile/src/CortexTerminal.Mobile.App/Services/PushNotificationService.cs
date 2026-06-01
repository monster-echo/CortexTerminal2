using Microsoft.Extensions.Logging;

#if IOS || ANDROID
using Plugin.Firebase.CloudMessaging;
#endif

namespace CortexTerminal.Mobile.App.Services;

public class PushNotificationService
{
    private readonly ILogger<PushNotificationService> _logger;

    public PushNotificationService(ILogger<PushNotificationService> logger)
    {
        _logger = logger;
    }

    public async Task<string?> GetFcmTokenAsync()
    {
        try
        {
#if IOS || ANDROID
            await CrossFirebaseCloudMessaging.Current.CheckIfValidAsync();
            return await CrossFirebaseCloudMessaging.Current.GetTokenAsync();
#else
            return null;
#endif
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to get FCM token.");
            return null;
        }
    }
}
