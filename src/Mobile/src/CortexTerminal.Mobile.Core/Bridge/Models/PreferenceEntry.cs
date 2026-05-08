namespace CortexTerminal.Mobile.Core.Bridge.Models;

public sealed record PreferenceEntry(
    string Key,
    string Title,
    string Category,
    string Description,
    bool Exists,
    string Value);
