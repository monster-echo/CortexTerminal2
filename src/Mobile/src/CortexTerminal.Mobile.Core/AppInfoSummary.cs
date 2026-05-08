namespace CortexTerminal.Mobile.Core;

public sealed record AppInfoSummary(
    string AppName,
    string AppVersion,
    string PackageIdentifier,
    string Platform,
    string SupportEmail,
    string PrivacyPolicyUrl,
    string TermsOfServiceUrl);
