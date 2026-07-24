using CortexTerminal.Mobile.Core.Bridge;

namespace CortexTerminal.Mobile.App.Services.Bridge;

public sealed partial class AppBridge
{
    [BridgeMethod]
    public Task<string> GetScrollbackPreferenceAsync()
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_authService is null) throw new InvalidOperationException("AuthService not configured");
            var pref = await _authService.GetScrollbackPreferenceAsync(default);
            return new { pref.MaxBytes, pref.MinBytes, pref.MaxAllowedBytes };
        });
    }

    [BridgeMethod]
    public Task<string> UpdateScrollbackPreferenceAsync(int maxBytes)
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_authService is null) throw new InvalidOperationException("AuthService not configured");
            var result = await _authService.UpdateScrollbackPreferenceAsync(maxBytes, default);
            if (!result.Success) throw new InvalidOperationException(result.Error ?? "Failed to update scrollback");
            return new { success = true };
        });
    }
}
