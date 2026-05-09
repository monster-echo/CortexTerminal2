namespace CortexTerminal.Mobile.Core.Configuration;

public sealed record AppSettings(
    string GatewayBaseUri,
    string SupportEmail,
    string PrivacyPolicyUrl,
    string TermsOfServiceUrl,
    bool EnableDiagnostics,
    bool EnableFeatureShowcase);
