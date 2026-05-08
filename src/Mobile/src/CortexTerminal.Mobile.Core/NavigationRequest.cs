namespace CortexTerminal.Mobile.Core;

public sealed record NavigationRequest(string Route, string? Payload = null);
