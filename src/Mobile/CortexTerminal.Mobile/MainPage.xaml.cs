using CortexTerminal.Mobile.Bridge;

#if IOS
using UIKit;
using WebKit;
#endif

namespace CortexTerminal.Mobile;

public partial class MainPage : ContentPage
{
	public MainPage(WebBridge bridge)
	{
		InitializeComponent();
		bridge.Attach(AppWebView);

		AppWebView.HandlerChanged += OnHandlerChanged;
	}

	private void OnHandlerChanged(object? sender, EventArgs e)
	{
#if IOS
		// Directly access the native WKWebView and disable its automatic
		// safe area content inset adjustment. This prevents iOS from
		// adding extra blank space at the top and bottom of the WebView.
		if (AppWebView.Handler?.PlatformView is WKWebView wk)
		{
			wk.ScrollView.ContentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentBehavior.Never;
		}
#endif
	}
}
