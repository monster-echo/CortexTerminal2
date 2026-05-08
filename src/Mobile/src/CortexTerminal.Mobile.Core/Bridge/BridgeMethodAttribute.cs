namespace CortexTerminal.Mobile.Core.Bridge;

/// <summary>
/// Marks a method as a bridge method that can be invoked from the web frontend.
/// Methods marked with this attribute are automatically exposed as API endpoints
/// by the DebugApi project via reflection.
/// </summary>
[AttributeUsage(AttributeTargets.Method, Inherited = false)]
public sealed class BridgeMethodAttribute : Attribute;
