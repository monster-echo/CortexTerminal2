using System.IO;
using CortexTerminal.Mobile.Core.Bridge;
using CortexTerminal.Mobile.App.Services.Support;

namespace CortexTerminal.Mobile.App.Services.Bridge;

public sealed partial class AppBridge
{
    private SupportService? _supportService;

    internal void SetSupportServices(SupportService supportService)
    {
        _supportService = supportService;
    }

    [BridgeMethod]
    public Task<string> GetSupportInfoAsync()
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_supportService is null) throw new InvalidOperationException("SupportService not configured");
            var info = await _supportService.GetSupportInfoAsync(default);
            if (info is null) return (object?)null;
            return new
            {
                qqGroup = info.QqGroup is null ? null : GroupDto(info.QqGroup),
                telegramGroup = info.TelegramGroup is null ? null : GroupDto(info.TelegramGroup),
                email = info.Email,
            };
        });
    }

    [BridgeMethod]
    public Task<string> PickFeedbackFileAsync()
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_supportService is null) throw new InvalidOperationException("SupportService not configured");
            var photos = await MainThread.InvokeOnMainThreadAsync(() => MediaPicker.Default.PickPhotosAsync());
            var photo = photos?.FirstOrDefault();
            if (photo is null) return (object?)null;
            var contentType = string.IsNullOrWhiteSpace(photo.ContentType) ? "image/png" : photo.ContentType;
            using var stream = await photo.OpenReadAsync();
            using var ms = new MemoryStream();
            await stream.CopyToAsync(ms);
            var bytes = ms.ToArray();
            var filename = string.IsNullOrWhiteSpace(photo.FileName) ? $"feedback-{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}.jpg" : photo.FileName;
            var imageUrl = await _supportService.UploadFeedbackFileAsync(bytes, filename, contentType, default);
            return new { imageUrl, filename };
        });
    }

    [BridgeMethod]
    public Task<string> SubmitFeedbackAsync(
        string type, string subtype, string content, string contact,
        string username, string lang, string appVersion, string attachmentsJson)
    {
        return ExecuteSafeAsync(async () =>
        {
            if (_supportService is null) throw new InvalidOperationException("SupportService not configured");
            var ticketId = await _supportService.SubmitFeedbackAsync(
                type, subtype, content, contact, username, lang, appVersion, attachmentsJson, default);
            return new { success = true, ticketId };
        });
    }

    [BridgeMethod]
    public Task<string> SaveImageToGalleryAsync(string imageUrl)
    {
        return ExecuteSafeVoidAsync(async () =>
        {
            if (_supportService is null) throw new InvalidOperationException("SupportService not configured");
            await _supportService.SaveImageToGalleryAsync(imageUrl, default);
        });
    }

    private static object GroupDto(SupportGroup g) => new
    {
        name = g.Name,
        number = g.Number,
        url = g.Url,
        qrCodeUrl = g.QrCodeUrl,
    };
}
