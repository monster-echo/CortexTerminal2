using Microsoft.Maui.Handlers;
using UIKit;
using WebKit;

namespace CortexTerminal.Mobile;

/// <summary>
/// Custom HybridWebView handler for iOS that disables WKWebView's
/// automatic safe area content inset adjustment. Without this,
/// iOS adds safe area insets to the WebView's scroll view,
/// causing blank space at the top and bottom of the screen.
/// </summary>
public class FullScreenHybridWebViewHandler : HybridWebViewHandler
{
	protected override WKWebView CreatePlatformView()
	{
		var webView = base.CreatePlatformView();

		// Prevent iOS from automatically adding safe area insets
		// to the WKWebView's scroll view.
		if (webView.ScrollView != null)
		{
			webView.ScrollView.ContentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentBehavior.Never;
		}

		return webView;
	}
}
