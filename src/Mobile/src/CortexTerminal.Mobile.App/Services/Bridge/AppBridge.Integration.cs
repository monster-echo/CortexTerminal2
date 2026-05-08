using CortexTerminal.Mobile.Core.Bridge;

namespace CortexTerminal.Mobile.App.Services.Bridge;

public sealed partial class AppBridge
{
    [BridgeMethod]
    public Task<string> OpenExternalLinkAsync(string url)
    {
        return ExecuteSafeVoidAsync(async () =>
        {
            if (string.IsNullOrWhiteSpace(url))
            {
                throw new ArgumentException("URL cannot be empty.", nameof(url));
            }

            await Browser.Default.OpenAsync(url, BrowserLaunchMode.SystemPreferred);
        });
    }

    [BridgeMethod]
    public Task<string> ShareTextAsync(string title, string text)
    {
        return ExecuteSafeVoidAsync(async () =>
        {
            await Share.Default.RequestAsync(new ShareTextRequest
            {
                Title = title,
                Text = text,
            });
        });
    }

    [BridgeMethod]
    public Task<string> ComposeSupportEmailAsync(string subject, string body, string? recipient = null)
    {
        return ExecuteSafeVoidAsync(async () =>
        {
            var finalRecipient = string.IsNullOrWhiteSpace(recipient) ? _appSettings.SupportEmail : recipient;
            if (Email.Default.IsComposeSupported)
            {
                var message = new EmailMessage
                {
                    Subject = subject,
                    Body = body,
                    To = new List<string> { finalRecipient },
                };

                await Email.Default.ComposeAsync(message);
                return;
            }

            var mailto = $"mailto:{Uri.EscapeDataString(finalRecipient)}?subject={Uri.EscapeDataString(subject)}&body={Uri.EscapeDataString(body)}";
            await Browser.Default.OpenAsync(mailto, BrowserLaunchMode.SystemPreferred);
        });
    }
}