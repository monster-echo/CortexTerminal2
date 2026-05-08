using System.IO;
using CortexTerminal.Mobile.Core.Bridge;
using CortexTerminal.Mobile.Core.Bridge.Models;

namespace CortexTerminal.Mobile.App.Services.Bridge;

public sealed partial class AppBridge
{
    [BridgeMethod]
    public Task<string> GetSystemInfoAsync()
    {
        return ExecuteSafeAsync(() => Task.FromResult(new BridgeSystemInfo
        {
            Platform = DeviceInfo.Platform.ToString(),
            AppVersion = AppInfo.Current.VersionString,
            DeviceModel = DeviceInfo.Model,
            Manufacturer = DeviceInfo.Manufacturer,
            DeviceName = DeviceInfo.Name,
            OperatingSystem = DeviceInfo.VersionString,
        }));
    }

    [BridgeMethod]
    public Task<string> PickPhotoAsync()
    {
        return ExecuteSafeAsync(async () =>
        {
            var files = await MainThread.InvokeOnMainThreadAsync(() => MediaPicker.Default.PickPhotosAsync());
            var file = files?.FirstOrDefault();
            return file is null ? null : await CreateMediaAssetAsync(file, "photo-library");
        });
    }

    [BridgeMethod]
    public Task<string> CapturePhotoAsync()
    {
        return ExecuteSafeAsync(async () =>
        {
            if (!MediaPicker.Default.IsCaptureSupported)
            {
                throw new NotSupportedException("Camera capture is not supported on this device.");
            }

            var file = await MainThread.InvokeOnMainThreadAsync(() => MediaPicker.Default.CapturePhotoAsync());
            return file is null ? null : await CreateMediaAssetAsync(file, "camera");
        });
    }

    [BridgeMethod]
    public Task<string> PickVideoAsync()
    {
        return ExecuteSafeAsync(async () =>
        {
            var files = await MainThread.InvokeOnMainThreadAsync(() => MediaPicker.Default.PickVideosAsync());
            var file = files?.FirstOrDefault();
            return file is null ? null : await CreateMediaAssetAsync(file, "video-library");
        });
    }

    [BridgeMethod]
    public Task<string> CaptureVideoAsync()
    {
        return ExecuteSafeAsync(async () =>
        {
            if (!MediaPicker.Default.IsCaptureSupported)
            {
                throw new NotSupportedException("Video capture is not supported on this device.");
            }

            var file = await MainThread.InvokeOnMainThreadAsync(() => MediaPicker.Default.CaptureVideoAsync());
            return file is null ? null : await CreateMediaAssetAsync(file, "video-camera");
        });
    }

    private async Task<object> CreateMediaAssetAsync(FileResult file, string source)
    {
        var contentType = string.IsNullOrWhiteSpace(file.ContentType)
            ? GuessContentType(file.FileName)
            : file.ContentType;
        var extension = Path.GetExtension(file.FileName);
        if (string.IsNullOrWhiteSpace(extension))
        {
            extension = GuessExtension(contentType);
        }

        var cacheFileName = $"{source}-{Guid.NewGuid():N}{extension}";
        var cachePath = Path.Combine(FileSystem.CacheDirectory, cacheFileName);

        await using (var stream = await file.OpenReadAsync())
        await using (var target = File.Create(cachePath))
        {
            await stream.CopyToAsync(target);
        }

        var fileSizeBytes = new FileInfo(cachePath).Length;

        return new
        {
            fileName = file.FileName,
            contentType,
            fileSizeBytes,
            source,
            localUrl = RegisterWebFile(cachePath, contentType, file.FileName),
        };
    }
}