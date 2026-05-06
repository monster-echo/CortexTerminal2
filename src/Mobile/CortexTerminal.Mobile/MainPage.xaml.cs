using CortexTerminal.Mobile.Bridge;

namespace CortexTerminal.Mobile;

public partial class MainPage : ContentPage
{
	public MainPage(WebBridge bridge)
	{
		InitializeComponent();
		bridge.Attach(AppWebView);
	}
}
