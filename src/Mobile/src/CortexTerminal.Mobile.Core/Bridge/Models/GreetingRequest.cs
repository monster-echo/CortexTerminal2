namespace CortexTerminal.Mobile.Core.Bridge.Models;

public sealed class GreetingRequest
{
    public string Name { get; set; } = string.Empty;
    public string Language { get; set; } = "en";
}
