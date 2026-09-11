import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Corterm'**
  String get appName;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @gatewayUrl.
  ///
  /// In en, this message translates to:
  /// **'Gateway URL'**
  String get gatewayUrl;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber;

  /// No description provided for @verificationCode.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get verificationCode;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get sendCode;

  /// No description provided for @codeSentTo.
  ///
  /// In en, this message translates to:
  /// **'Code sent to {phone}'**
  String codeSentTo(String phone);

  /// No description provided for @passwordLogin.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLogin;

  /// No description provided for @phoneLogin.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phoneLogin;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get signingIn;

  /// No description provided for @sendingCode.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get sendingCode;

  /// No description provided for @slideToVerify.
  ///
  /// In en, this message translates to:
  /// **'Slide to verify'**
  String get slideToVerify;

  /// No description provided for @verifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying…'**
  String get verifying;

  /// No description provided for @phoneCodeResendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String phoneCodeResendIn(int seconds);

  /// No description provided for @invalidGatewayUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid gateway URL'**
  String get invalidGatewayUrl;

  /// No description provided for @invalidUsername.
  ///
  /// In en, this message translates to:
  /// **'Enter your username'**
  String get invalidUsername;

  /// No description provided for @invalidPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get invalidPassword;

  /// No description provided for @invalidPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number'**
  String get invalidPhone;

  /// No description provided for @invalidCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the verification code'**
  String get invalidCode;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign in failed'**
  String get loginFailed;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTitle;

  /// No description provided for @runningSessions.
  ///
  /// In en, this message translates to:
  /// **'Running Sessions'**
  String get runningSessions;

  /// No description provided for @recentSessions.
  ///
  /// In en, this message translates to:
  /// **'Recent Sessions'**
  String get recentSessions;

  /// No description provided for @workers.
  ///
  /// In en, this message translates to:
  /// **'Workers'**
  String get workers;

  /// No description provided for @newSession.
  ///
  /// In en, this message translates to:
  /// **'New Session'**
  String get newSession;

  /// No description provided for @noActiveSessions.
  ///
  /// In en, this message translates to:
  /// **'No active sessions'**
  String get noActiveSessions;

  /// No description provided for @noActiveSessionsHint.
  ///
  /// In en, this message translates to:
  /// **'Start a remote terminal to begin.'**
  String get noActiveSessionsHint;

  /// No description provided for @noWorkers.
  ///
  /// In en, this message translates to:
  /// **'No workers connected'**
  String get noWorkers;

  /// No description provided for @workerOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get workerOffline;

  /// No description provided for @workerOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get workerOnline;

  /// No description provided for @allSessions.
  ///
  /// In en, this message translates to:
  /// **'All Sessions'**
  String get allSessions;

  /// No description provided for @noSessions.
  ///
  /// In en, this message translates to:
  /// **'No sessions yet'**
  String get noSessions;

  /// No description provided for @sessionRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename session'**
  String get sessionRenameTitle;

  /// No description provided for @sessionNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Session name'**
  String get sessionNameLabel;

  /// No description provided for @terminateSession.
  ///
  /// In en, this message translates to:
  /// **'Terminate Session'**
  String get terminateSession;

  /// No description provided for @deleteSession.
  ///
  /// In en, this message translates to:
  /// **'Delete Session'**
  String get deleteSession;

  /// No description provided for @deleteSessionConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String deleteSessionConfirmTitle(Object name);

  /// No description provided for @deleteSessionConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the session record. The remote process is already stopped.'**
  String get deleteSessionConfirmBody;

  /// No description provided for @terminateConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Terminate {name}?'**
  String terminateConfirmTitle(Object name);

  /// No description provided for @terminateConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This will stop the remote session and the running process.'**
  String get terminateConfirmBody;

  /// No description provided for @terminate.
  ///
  /// In en, this message translates to:
  /// **'Terminate'**
  String get terminate;

  /// No description provided for @statusAttached.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get statusAttached;

  /// No description provided for @statusDetachedGracePeriod.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get statusDetachedGracePeriod;

  /// No description provided for @statusRecovering.
  ///
  /// In en, this message translates to:
  /// **'Recovering'**
  String get statusRecovering;

  /// No description provided for @statusExited.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get statusExited;

  /// No description provided for @statusExpired.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get statusExpired;

  /// No description provided for @groupActive.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get groupActive;

  /// No description provided for @groupEnded.
  ///
  /// In en, this message translates to:
  /// **'ENDED'**
  String get groupEnded;

  /// No description provided for @sessionDetails.
  ///
  /// In en, this message translates to:
  /// **'Session Details'**
  String get sessionDetails;

  /// No description provided for @sessionId.
  ///
  /// In en, this message translates to:
  /// **'Session ID'**
  String get sessionId;

  /// No description provided for @agentKind.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get agentKind;

  /// No description provided for @worker.
  ///
  /// In en, this message translates to:
  /// **'Worker'**
  String get worker;

  /// No description provided for @createdAt.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get createdAt;

  /// No description provided for @lastActivity.
  ///
  /// In en, this message translates to:
  /// **'Last activity'**
  String get lastActivity;

  /// No description provided for @exitCode.
  ///
  /// In en, this message translates to:
  /// **'Exit code'**
  String get exitCode;

  /// No description provided for @exitReason.
  ///
  /// In en, this message translates to:
  /// **'Exit reason'**
  String get exitReason;

  /// No description provided for @sessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get sessions;

  /// No description provided for @current.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get current;

  /// No description provided for @selectSession.
  ///
  /// In en, this message translates to:
  /// **'Select session'**
  String get selectSession;

  /// No description provided for @createSessionFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create session'**
  String get createSessionFailed;

  /// No description provided for @chooseWorker.
  ///
  /// In en, this message translates to:
  /// **'Choose worker'**
  String get chooseWorker;

  /// No description provided for @runtimeTerminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get runtimeTerminal;

  /// No description provided for @runtimeShell.
  ///
  /// In en, this message translates to:
  /// **'Shell'**
  String get runtimeShell;

  /// No description provided for @runtimeShellHint.
  ///
  /// In en, this message translates to:
  /// **'Run any CLI — Claude Code, Codex, and other agents are detected automatically.'**
  String get runtimeShellHint;

  /// No description provided for @connection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connection;

  /// No description provided for @connectionState.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get connectionState;

  /// No description provided for @gateway.
  ///
  /// In en, this message translates to:
  /// **'Gateway'**
  String get gateway;

  /// No description provided for @latency.
  ///
  /// In en, this message translates to:
  /// **'Latency'**
  String get latency;

  /// No description provided for @network.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get network;

  /// No description provided for @networkWifi.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi'**
  String get networkWifi;

  /// No description provided for @networkMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile data'**
  String get networkMobile;

  /// No description provided for @networkEthernet.
  ///
  /// In en, this message translates to:
  /// **'Ethernet'**
  String get networkEthernet;

  /// No description provided for @networkNone.
  ///
  /// In en, this message translates to:
  /// **'No network'**
  String get networkNone;

  /// No description provided for @connLive.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connLive;

  /// No description provided for @connConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connConnecting;

  /// No description provided for @connReplaying.
  ///
  /// In en, this message translates to:
  /// **'Restoring…'**
  String get connReplaying;

  /// No description provided for @connReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get connReconnecting;

  /// No description provided for @connClosed.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get connClosed;

  /// No description provided for @connExited.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get connExited;

  /// No description provided for @connError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get connError;

  /// No description provided for @connIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get connIdle;

  /// No description provided for @gatewayConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get gatewayConnected;

  /// No description provided for @gatewayDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get gatewayDisconnected;

  /// No description provided for @ms.
  ///
  /// In en, this message translates to:
  /// **'{n} ms'**
  String ms(int n);

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @files.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get files;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @reconnectBanner.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get reconnectBanner;

  /// No description provided for @connectBanner.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connectBanner;

  /// No description provided for @restoringBanner.
  ///
  /// In en, this message translates to:
  /// **'Restoring session…'**
  String get restoringBanner;

  /// No description provided for @sessionEndedBanner.
  ///
  /// In en, this message translates to:
  /// **'Session ended ({reason})'**
  String sessionEndedBanner(String reason);

  /// No description provided for @sessionErrorBanner.
  ///
  /// In en, this message translates to:
  /// **'Connection error'**
  String get sessionErrorBanner;

  /// No description provided for @displacedBanner.
  ///
  /// In en, this message translates to:
  /// **'Opened elsewhere — tap to reconnect'**
  String get displacedBanner;

  /// No description provided for @tapToReconnect.
  ///
  /// In en, this message translates to:
  /// **'Tap to reconnect'**
  String get tapToReconnect;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @terminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get terminal;

  /// No description provided for @keyboardToolbar.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Toolbar'**
  String get keyboardToolbar;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @appearanceSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get appearanceSystem;

  /// No description provided for @appearanceLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get appearanceLight;

  /// No description provided for @appearanceDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get appearanceDark;

  /// No description provided for @terminalFontSize.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get terminalFontSize;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get languageChinese;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePassword;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get currentPassword;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @passwordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get passwordChanged;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get logout;

  /// No description provided for @logoutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out of Corterm?'**
  String get logoutConfirm;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get appVersion;

  /// No description provided for @gatewayVersion.
  ///
  /// In en, this message translates to:
  /// **'Gateway version'**
  String get gatewayVersion;

  /// No description provided for @fontSizeFmt.
  ///
  /// In en, this message translates to:
  /// **'{pt} pt'**
  String fontSizeFmt(double pt);

  /// No description provided for @legal.
  ///
  /// In en, this message translates to:
  /// **'Legal & Policies'**
  String get legal;

  /// No description provided for @legalVersionCaption.
  ///
  /// In en, this message translates to:
  /// **'Effective: {date}'**
  String legalVersionCaption(String date);

  /// No description provided for @legalIndexIntro.
  ///
  /// In en, this message translates to:
  /// **'The following documents govern your use of Corterm. The Chinese version is authoritative.'**
  String get legalIndexIntro;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @privacyPolicyDesc.
  ///
  /// In en, this message translates to:
  /// **'What we collect, how it is used and stored.'**
  String get privacyPolicyDesc;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @termsOfServiceDesc.
  ///
  /// In en, this message translates to:
  /// **'Scope of the service, acceptable use, liability.'**
  String get termsOfServiceDesc;

  /// No description provided for @consentPrefix.
  ///
  /// In en, this message translates to:
  /// **'I have read and agree to the '**
  String get consentPrefix;

  /// No description provided for @consentAnd.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get consentAnd;

  /// No description provided for @consentAlertTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms & Privacy'**
  String get consentAlertTitle;

  /// No description provided for @consentAlertBody.
  ///
  /// In en, this message translates to:
  /// **'To protect your lawful rights and interests, please read and agree to the Terms of Service and Privacy Policy.'**
  String get consentAlertBody;

  /// No description provided for @agree.
  ///
  /// In en, this message translates to:
  /// **'Agree'**
  String get agree;

  /// No description provided for @disagree.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get disagree;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this account?'**
  String get deleteAccountConfirmTitle;

  /// No description provided for @deleteAccountConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The account, its sessions and preferences will be permanently deleted on the server. This cannot be undone.'**
  String get deleteAccountConfirmBody;

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'Mobile AI Agent Workspace'**
  String get aboutTagline;

  /// No description provided for @filesTitle.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get filesTitle;

  /// No description provided for @upload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get upload;

  /// No description provided for @uploadDone.
  ///
  /// In en, this message translates to:
  /// **'Upload complete'**
  String get uploadDone;

  /// No description provided for @uploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed'**
  String get uploadFailed;

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get downloadFailed;

  /// No description provided for @emptyFolder.
  ///
  /// In en, this message translates to:
  /// **'Empty folder'**
  String get emptyFolder;

  /// No description provided for @listTruncated.
  ///
  /// In en, this message translates to:
  /// **'Listing truncated (server limit reached).'**
  String get listTruncated;

  /// No description provided for @workersTitle.
  ///
  /// In en, this message translates to:
  /// **'Workers'**
  String get workersTitle;

  /// No description provided for @sessionCount.
  ///
  /// In en, this message translates to:
  /// **'{n} sessions'**
  String sessionCount(int n);

  /// No description provided for @workerHostname.
  ///
  /// In en, this message translates to:
  /// **'Hostname'**
  String get workerHostname;

  /// No description provided for @workerOs.
  ///
  /// In en, this message translates to:
  /// **'OS'**
  String get workerOs;

  /// No description provided for @workerVersion.
  ///
  /// In en, this message translates to:
  /// **'Worker version'**
  String get workerVersion;

  /// No description provided for @upgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get upgrade;

  /// No description provided for @upgradeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Upgrade this worker now?'**
  String get upgradeConfirm;

  /// No description provided for @openSessions.
  ///
  /// In en, this message translates to:
  /// **'Open Sessions'**
  String get openSessions;

  /// No description provided for @diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnostics;

  /// No description provided for @gatewayReachable.
  ///
  /// In en, this message translates to:
  /// **'Gateway reachability'**
  String get gatewayReachable;

  /// No description provided for @diagnosticTesting.
  ///
  /// In en, this message translates to:
  /// **'Testing…'**
  String get diagnosticTesting;

  /// No description provided for @diagnosticFail.
  ///
  /// In en, this message translates to:
  /// **'Unreachable'**
  String get diagnosticFail;

  /// No description provided for @platform.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get platform;

  /// No description provided for @keepScreenAwake.
  ///
  /// In en, this message translates to:
  /// **'Keep screen awake'**
  String get keepScreenAwake;

  /// No description provided for @otherLoginMethods.
  ///
  /// In en, this message translates to:
  /// **'Other sign-in methods'**
  String get otherLoginMethods;

  /// No description provided for @oauthPending.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {provider}…'**
  String oauthPending(String provider);

  /// No description provided for @oauthFailed.
  ///
  /// In en, this message translates to:
  /// **'{provider} sign-in failed'**
  String oauthFailed(String provider);

  /// No description provided for @createSession.
  ///
  /// In en, this message translates to:
  /// **'Create Session'**
  String get createSession;

  /// No description provided for @creating.
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get creating;

  /// No description provided for @selectWorker.
  ///
  /// In en, this message translates to:
  /// **'Select worker'**
  String get selectWorker;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @tunnelTitle.
  ///
  /// In en, this message translates to:
  /// **'Port Forwarding'**
  String get tunnelTitle;

  /// No description provided for @tunnelPortLabel.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get tunnelPortLabel;

  /// No description provided for @tunnelPortPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'1-65535'**
  String get tunnelPortPlaceholder;

  /// No description provided for @tunnelEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tunnels yet'**
  String get tunnelEmpty;

  /// No description provided for @tunnelExpires.
  ///
  /// In en, this message translates to:
  /// **'Expires {time}'**
  String tunnelExpires(String time);

  /// No description provided for @tunnelCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get tunnelCopyLink;

  /// No description provided for @tunnelOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get tunnelOpen;

  /// No description provided for @tunnelRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get tunnelRevoke;

  /// No description provided for @tunnelInvalidPort.
  ///
  /// In en, this message translates to:
  /// **'Port must be 1-65535'**
  String get tunnelInvalidPort;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @displayNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayNameLabel;

  /// No description provided for @hasPassword.
  ///
  /// In en, this message translates to:
  /// **'Password set'**
  String get hasPassword;

  /// No description provided for @avatarUpdated.
  ///
  /// In en, this message translates to:
  /// **'Avatar updated'**
  String get avatarUpdated;

  /// No description provided for @activateTitle.
  ///
  /// In en, this message translates to:
  /// **'Device activation'**
  String get activateTitle;

  /// No description provided for @activateIntro.
  ///
  /// In en, this message translates to:
  /// **'Enter the activation code shown by your device or CLI to authorize it with your account.'**
  String get activateIntro;

  /// No description provided for @activateCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Activation code'**
  String get activateCodeLabel;

  /// No description provided for @activateConfirm.
  ///
  /// In en, this message translates to:
  /// **'Authorize'**
  String get activateConfirm;

  /// No description provided for @activateDone.
  ///
  /// In en, this message translates to:
  /// **'Device authorized'**
  String get activateDone;

  /// No description provided for @activateInvalidCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid or expired code'**
  String get activateInvalidCode;

  /// No description provided for @deviceAccess.
  ///
  /// In en, this message translates to:
  /// **'Device access'**
  String get deviceAccess;

  /// No description provided for @scrollbackQuota.
  ///
  /// In en, this message translates to:
  /// **'Server scrollback'**
  String get scrollbackQuota;

  /// No description provided for @terminalSize.
  ///
  /// In en, this message translates to:
  /// **'Terminal size'**
  String get terminalSize;

  /// No description provided for @supportTitle.
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get supportTitle;

  /// No description provided for @supportEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get supportEmail;

  /// No description provided for @supportSaveQr.
  ///
  /// In en, this message translates to:
  /// **'Save QR'**
  String get supportSaveQr;

  /// No description provided for @feedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get feedbackTitle;

  /// No description provided for @feedbackBug.
  ///
  /// In en, this message translates to:
  /// **'Bug report'**
  String get feedbackBug;

  /// No description provided for @feedbackSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Suggestion'**
  String get feedbackSuggestion;

  /// No description provided for @feedbackContent.
  ///
  /// In en, this message translates to:
  /// **'Describe the issue'**
  String get feedbackContent;

  /// No description provided for @feedbackContentPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'What happened? What did you expect?'**
  String get feedbackContentPlaceholder;

  /// No description provided for @feedbackContact.
  ///
  /// In en, this message translates to:
  /// **'Contact (optional)'**
  String get feedbackContact;

  /// No description provided for @feedbackContactPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Email / Telegram / QQ'**
  String get feedbackContactPlaceholder;

  /// No description provided for @feedbackAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments ({cur}/{max})'**
  String feedbackAttachments(int cur, int max);

  /// No description provided for @feedbackAddImage.
  ///
  /// In en, this message translates to:
  /// **'Add image'**
  String get feedbackAddImage;

  /// No description provided for @feedbackSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting…'**
  String get feedbackSubmitting;

  /// No description provided for @feedbackSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get feedbackSubmit;

  /// No description provided for @feedbackDone.
  ///
  /// In en, this message translates to:
  /// **'Feedback submitted. Thank you!'**
  String get feedbackDone;

  /// No description provided for @installWorkerTitle.
  ///
  /// In en, this message translates to:
  /// **'Install a worker'**
  String get installWorkerTitle;

  /// No description provided for @installWorkerIntro.
  ///
  /// In en, this message translates to:
  /// **'Run the installer on your machine to connect it as a worker, then activate it with the command shown there.'**
  String get installWorkerIntro;

  /// No description provided for @installActivateHint.
  ///
  /// In en, this message translates to:
  /// **'After install, run \'corterm activate\' and confirm the code under Settings → Device access.'**
  String get installActivateHint;

  /// No description provided for @installCopyCommand.
  ///
  /// In en, this message translates to:
  /// **'Copy command'**
  String get installCopyCommand;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
