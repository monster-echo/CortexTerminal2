namespace CortexTerminal.Mobile;

public partial class AppShell : Shell
{
	public AppShell(MainPage mainPage)
	{
		InitializeComponent();
		Items.Add(new ShellContent
		{
			Route = nameof(MainPage),
			Title = "Home",
			Content = mainPage,
		});
	}
}
