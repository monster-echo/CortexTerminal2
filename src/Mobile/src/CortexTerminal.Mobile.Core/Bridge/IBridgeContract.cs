using CortexTerminal.Mobile.Core.Bridge.Models;

namespace CortexTerminal.Mobile.Core.Bridge;

/// <summary>
/// Defines the contract for bridge methods that can be invoked from the web frontend.
/// Implemented by <c>AppBridge</c> (MAUI native) and <c>HttpBridge</c> (DebugApi).
/// </summary>
public interface IBridgeContract
{
    // Device
    [BridgeMethod]
    Task<string> GetSystemInfoAsync();

    [BridgeMethod]
    Task<string> PickPhotoAsync();

    [BridgeMethod]
    Task<string> CapturePhotoAsync();

    [BridgeMethod]
    Task<string> PickVideoAsync();

    [BridgeMethod]
    Task<string> CaptureVideoAsync();

    // Feedback
    [BridgeMethod]
    Task<string> ShowToastAsync(string message);

    [BridgeMethod]
    Task<string> ShowToastWithDurationAsync(string message, string duration);

    [BridgeMethod]
    Task<string> DismissToastAsync();

    [BridgeMethod]
    Task<string> ShowSnackbarAsync(string message);

    [BridgeMethod]
    Task<string> ShowSnackbarWithOptionsAsync(string message, string? actionButtonText = null, string? duration = null);

    [BridgeMethod]
    Task<string> DismissSnackbarAsync();

    [BridgeMethod]
    Task<string> HapticsAsync(string type);

    // Info
    [BridgeMethod]
    Task<string> GetPlatformInfoAsync();

    [BridgeMethod]
    Task<string> GetBridgeCapabilitiesAsync();

    [BridgeMethod]
    Task<string> GetAppInfoSummaryAsync();

    // Integration
    [BridgeMethod]
    Task<string> OpenExternalLinkAsync(string url);

    [BridgeMethod]
    Task<string> ShareTextAsync(string title, string text);

    [BridgeMethod]
    Task<string> ComposeSupportEmailAsync(string subject, string body, string? recipient = null);

    // Interop
    [BridgeMethod]
    Task<string> StartBinaryStreamToJsAsync(int chunkByteLength = 256, int chunkCount = 20, int intervalMs = 250);

    [BridgeMethod]
    Task<string> StopBinaryStreamToJsAsync();

    [BridgeMethod]
    Task<string> EchoTextAsync(string message);

    [BridgeMethod]
    Task<string> EchoBinaryAsync(string base64);

    [BridgeMethod]
    Task<string> SendTextMessageToJsAsync(string message);

    [BridgeMethod]
    Task<string> SendBinaryMessageToJsAsync(int byteLength = 32);

    // Preferences
    [BridgeMethod]
    Task<string> GetStringValueAsync(string key);

    [BridgeMethod]
    Task<string> SetStringValueAsync(string key, string value);

    [BridgeMethod]
    Task<string> RemoveStringValueAsync(string key);

    [BridgeMethod]
    Task<string> GetPreferenceEntriesAsync();

    [BridgeMethod]
    Task<string> GetPendingNavigationAsync();

    [BridgeMethod]
    Task<string> SetPendingNavigationAsync(string route, string? payload = null);

    [BridgeMethod]
    Task<string> ClearPendingNavigationAsync();

    // 认证
    [BridgeMethod]
    Task<string> SendPhoneCodeAsync(string phone);

    [BridgeMethod]
    Task<string> VerifyPhoneCodeAsync(string phone, string code);

    [BridgeMethod]
    Task<string> StartOAuthAsync(string provider);

    [BridgeMethod]
    Task<string> GetSessionAsync();

    [BridgeMethod]
    Task<string> LogoutAsync();

    [BridgeMethod]
    Task<string> GuestLoginAsync();

    // Demo
    [BridgeMethod]
    Task<string> HelloAsync();

    [BridgeMethod]
    Task<string> GreetAsync(GreetingRequest request);
}
