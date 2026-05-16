using System.Runtime.InteropServices;
using CortexTerminal.Mobile.App.Services.Auth;
using Foundation;
using Microsoft.Extensions.DependencyInjection;
using UIKit;

namespace CortexTerminal.Mobile.App;

[Register("AppDelegate")]
public class AppDelegate : MauiUIApplicationDelegate
{
    protected override MauiApp CreateMauiApp() => MauiProgram.CreateMauiApp();

    public override bool FinishedLaunching(UIApplication application, NSDictionary? launchOptions)
    {
        var result = base.FinishedLaunching(application, launchOptions);
        HideKeyboardAccessoryBar();
        return result;
    }

    /// <summary>
    /// Swizzles WKContentView's inputAccessoryView to return nil,
    /// hiding the iOS keyboard accessory bar (arrows + Done button)
    /// that appears above the keyboard in WKWebView.
    /// This is a one-time global operation that affects all WKWebView instances.
    /// </summary>
    private static unsafe void HideKeyboardAccessoryBar()
    {
        var selector = sel_registerName("inputAccessoryView");
        var nilImp = (IntPtr)_returnNilPointer;
        var targets = new[] { "WKContentView", "_WKContentView" };

        foreach (var targetName in targets)
        {
            var targetClass = objc_getClass(targetName);
            if (targetClass == IntPtr.Zero) continue;

            var targetMethod = class_getInstanceMethod(targetClass, selector);
            if (targetMethod == IntPtr.Zero) continue;

            method_setImplementation(targetMethod, nilImp);
        }
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static IntPtr ReturnNil(IntPtr self, IntPtr cmd) => IntPtr.Zero;

    private static readonly unsafe delegate* unmanaged[Cdecl]<IntPtr, IntPtr, IntPtr> _returnNilPointer = &ReturnNil;

    #region ObjC Runtime P/Invoke

    [DllImport("/usr/lib/libobjc.dylib")]
    private static extern IntPtr objc_getClass(string name);

    [DllImport("/usr/lib/libobjc.dylib")]
    private static extern IntPtr sel_registerName(string name);

    [DllImport("/usr/lib/libobjc.dylib")]
    private static extern IntPtr class_getInstanceMethod(IntPtr cls, IntPtr sel);

    [DllImport("/usr/lib/libobjc.dylib")]
    private static extern IntPtr method_setImplementation(IntPtr method, IntPtr imp);

    #endregion

    public override bool OpenUrl(UIApplication application, NSUrl url, NSDictionary options)
    {
        if (base.OpenUrl(application, url, options))
            return true;

        if (url.Scheme == "corterm.mobile")
        {
            var uri = new Uri(url.AbsoluteString!);
            _ = HandleDeepLinkAsync(uri);
            return true;
        }
        return false;
    }

    private async Task HandleDeepLinkAsync(Uri uri)
    {
        try
        {
            var services = Microsoft.Maui.Controls.Application.Current?.Handler?.MauiContext?.Services;
            var oauthService = services?.GetService<OAuthService>();
            if (oauthService is not null)
            {
                await oauthService.HandleDeepLinkAsync(uri, default);
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[AppDelegate] Deep link error: {ex.Message}");
        }
    }
}
