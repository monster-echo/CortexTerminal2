namespace CortexTerminal.Mobile.Core.Bridge.Models;

public sealed class GreetingResponse
{
    public string Greeting { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Language { get; set; } = string.Empty;
    public string Timestamp { get; set; } = string.Empty;
    public int WordCount { get; set; }
}
