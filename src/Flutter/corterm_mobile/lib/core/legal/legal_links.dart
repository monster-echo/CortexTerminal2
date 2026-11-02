/// Public legal URLs for store metadata and the subscription paywall.
///
/// App Store Connect keeps the License Agreement field empty, so Apple's
/// standard EULA governs the app. The same URL is required in the App Store
/// description for every localization (Guideline 3.1.2).
class LegalLinks {
  const LegalLinks._();

  static const String termsOfUse =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

  static const String privacyPolicy = 'https://corterm.rwecho.top/privacy';
}
