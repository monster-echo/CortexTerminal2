using CortexTerminal.Mobile.Core.Bridge;
using CortexTerminal.Mobile.Core.Bridge.Models;

namespace CortexTerminal.Mobile.App.Services.Bridge;

public sealed partial class AppBridge
{
    private static readonly PreferenceDescriptor[] KnownPreferenceDescriptors =
    [
        new("template.bridge.demo", "Bridge demo value", "bridge", "JS 和 C# 交互页的 roundtrip 示例。"),
        new("template.camera.last", "Last camera metadata", "camera", "最近一次拍照写入的元数据缓存。"),
        new("template.photos.last", "Last photo metadata", "photos", "最近一次相册选图写入的元数据缓存。"),
        new("template.video.last", "Last video metadata", "video", "最近一次视频选择或拍摄写入的元数据缓存。"),
        new(PendingNavigationRouteKey, "Pending navigation route", "notifications", "通知/深链待处理跳转的目标路由。"),
        new(PendingNavigationPayloadKey, "Pending navigation payload", "notifications", "通知/深链待处理跳转附带的 payload。"),
    ];

    [BridgeMethod]
    public Task<string> GetStringValueAsync(string key)
    {
        return ExecuteSafeAsync(() => Task.FromResult(Preferences.Default.Get(key, string.Empty)));
    }

    [BridgeMethod]
    public Task<string> SetStringValueAsync(string key, string value)
    {
        return ExecuteSafeVoidAsync(() =>
        {
            Preferences.Default.Set(key, value);
            return Task.CompletedTask;
        });
    }

    [BridgeMethod]
    public Task<string> RemoveStringValueAsync(string key)
    {
        return ExecuteSafeVoidAsync(() =>
        {
            Preferences.Default.Remove(key);
            return Task.CompletedTask;
        });
    }

    [BridgeMethod]
    public Task<string> GetPreferenceEntriesAsync()
    {
        return ExecuteSafeAsync(() => Task.FromResult(
            KnownPreferenceDescriptors
                .Select(descriptor => new PreferenceEntry(
                    descriptor.Key,
                    descriptor.Title,
                    descriptor.Category,
                    descriptor.Description,
                    Preferences.Default.ContainsKey(descriptor.Key),
                    Preferences.Default.Get(descriptor.Key, string.Empty)))
                .OrderBy(entry => entry.Category)
                .ThenBy(entry => entry.Key)
                .ToArray()));
    }

    [BridgeMethod]
    public Task<string> GetPendingNavigationAsync()
    {
        return ExecuteSafeAsync(() =>
        {
            var route = Preferences.Default.Get(PendingNavigationRouteKey, string.Empty);
            var payload = Preferences.Default.Get(PendingNavigationPayloadKey, string.Empty);

            if (string.IsNullOrWhiteSpace(route))
            {
                return Task.FromResult(new PendingNavigationState { HasPending = false });
            }

            Preferences.Default.Remove(PendingNavigationRouteKey);
            Preferences.Default.Remove(PendingNavigationPayloadKey);

            return Task.FromResult(new PendingNavigationState
            {
                HasPending = true,
                Route = route,
                Payload = payload,
            });
        });
    }

    [BridgeMethod]
    public Task<string> SetPendingNavigationAsync(string route, string? payload = null)
    {
        return ExecuteSafeVoidAsync(() =>
        {
            Preferences.Default.Set(PendingNavigationRouteKey, route);
            Preferences.Default.Set(PendingNavigationPayloadKey, payload ?? string.Empty);
            return Task.CompletedTask;
        });
    }

    [BridgeMethod]
    public Task<string> ClearPendingNavigationAsync()
    {
        return ExecuteSafeVoidAsync(() =>
        {
            Preferences.Default.Remove(PendingNavigationRouteKey);
            Preferences.Default.Remove(PendingNavigationPayloadKey);
            return Task.CompletedTask;
        });
    }

    private sealed record PreferenceDescriptor(string Key, string Title, string Category, string Description);
}