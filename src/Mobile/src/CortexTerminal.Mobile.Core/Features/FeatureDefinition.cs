namespace CortexTerminal.Mobile.Core.Features;

public sealed record FeatureDefinition(
    string Key,
    string Title,
    string Description,
    FeatureCategory Category,
    string Route,
    bool RequiresNativeBridge,
    IReadOnlyList<string>? Tags = null);
