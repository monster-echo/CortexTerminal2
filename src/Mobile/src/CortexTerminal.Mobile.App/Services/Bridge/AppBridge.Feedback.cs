using CommunityToolkit.Maui.Alerts;
using CortexTerminal.Mobile.Core.Bridge;
using Microsoft.Extensions.Logging;

namespace CortexTerminal.Mobile.App.Services.Bridge;

public sealed partial class AppBridge
{
    [BridgeMethod]
    public Task<string> ShowToastAsync(string message)
    {
        return ShowToastWithDurationAsync(message, "short");
    }

    [BridgeMethod]
    public Task<string> ShowToastWithDurationAsync(string message, string duration)
    {
        return ExecuteSafeVoidAsync(() => MainThread.InvokeOnMainThreadAsync(async () =>
        {
            var toastDuration = duration?.ToLowerInvariant() switch
            {
                "long" => CommunityToolkit.Maui.Core.ToastDuration.Long,
                _ => CommunityToolkit.Maui.Core.ToastDuration.Short,
            };

            var toast = Toast.Make(message, toastDuration);
            _activeToast = toast;
            await toast.Show(CancellationToken.None);
        }));
    }

    [BridgeMethod]
    public Task<string> DismissToastAsync()
    {
        return ExecuteSafeVoidAsync(() => MainThread.InvokeOnMainThreadAsync(async () =>
        {
            if (_activeToast is not null)
            {
                await _activeToast.Dismiss(CancellationToken.None);
                _activeToast = null;
            }
        }));
    }

    [BridgeMethod]
    public Task<string> ShowSnackbarAsync(string message)
    {
        return ShowSnackbarWithOptionsAsync(message, null, "short");
    }

    [BridgeMethod]
    public Task<string> ShowSnackbarWithOptionsAsync(string message, string? actionButtonText = null, string? duration = null)
    {
        return ExecuteSafeVoidAsync(() => MainThread.InvokeOnMainThreadAsync(async () =>
        {
            var snackbarDuration = duration?.ToLowerInvariant() switch
            {
                "long" => TimeSpan.FromSeconds(10),
                "indefinite" or "sticky" => TimeSpan.FromMinutes(5),
                _ => TimeSpan.FromSeconds(3),
            };

            Action? action = string.IsNullOrWhiteSpace(actionButtonText)
                ? null
                : () => logger.LogInformation("Snackbar action tapped: {ActionButtonText}", actionButtonText);

            var snackbar = Snackbar.Make(
                message,
                action,
                actionButtonText ?? string.Empty,
                snackbarDuration);

            _activeSnackbar = snackbar;
            await snackbar.Show(CancellationToken.None);
        }));
    }

    [BridgeMethod]
    public Task<string> DismissSnackbarAsync()
    {
        return ExecuteSafeVoidAsync(() => MainThread.InvokeOnMainThreadAsync(async () =>
        {
            if (_activeSnackbar is not null)
            {
                await _activeSnackbar.Dismiss(CancellationToken.None);
                _activeSnackbar = null;
            }
        }));
    }

    [BridgeMethod]
    public Task<string> HapticsAsync(string type)
    {
        return ExecuteSafeVoidAsync(() => MainThread.InvokeOnMainThreadAsync(() =>
        {
            var feedbackType = type?.ToLowerInvariant() switch
            {
                "longpress" or "heavy" => HapticFeedbackType.LongPress,
                _ => HapticFeedbackType.Click,
            };

            HapticFeedback.Default.Perform(feedbackType);
        }));
    }
}