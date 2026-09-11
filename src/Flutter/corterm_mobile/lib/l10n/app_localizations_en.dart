// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Corterm';

  @override
  String get cancel => 'Cancel';

  @override
  String get ok => 'OK';

  @override
  String get retry => 'Retry';

  @override
  String get delete => 'Delete';

  @override
  String get rename => 'Rename';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get paste => 'Paste';

  @override
  String get save => 'Save';

  @override
  String get unknown => 'Unknown';

  @override
  String get loading => 'Loading…';

  @override
  String get gatewayUrl => 'Gateway URL';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get phoneNumber => 'Phone number';

  @override
  String get verificationCode => 'Verification code';

  @override
  String get sendCode => 'Send code';

  @override
  String codeSentTo(String phone) {
    return 'Code sent to $phone';
  }

  @override
  String get passwordLogin => 'Password';

  @override
  String get phoneLogin => 'Phone';

  @override
  String get signIn => 'Sign in';

  @override
  String get signingIn => 'Signing in…';

  @override
  String get sendingCode => 'Sending…';

  @override
  String get slideToVerify => 'Slide to verify';

  @override
  String get verifying => 'Verifying…';

  @override
  String phoneCodeResendIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get invalidGatewayUrl => 'Enter a valid gateway URL';

  @override
  String get invalidUsername => 'Enter your username';

  @override
  String get invalidPassword => 'Enter your password';

  @override
  String get invalidPhone => 'Enter a valid phone number';

  @override
  String get invalidCode => 'Enter the verification code';

  @override
  String get loginFailed => 'Sign in failed';

  @override
  String get homeTitle => 'Home';

  @override
  String get runningSessions => 'Running Sessions';

  @override
  String get recentSessions => 'Recent Sessions';

  @override
  String get workers => 'Workers';

  @override
  String get newSession => 'New Session';

  @override
  String get noActiveSessions => 'No active sessions';

  @override
  String get noActiveSessionsHint => 'Start a remote terminal to begin.';

  @override
  String get noWorkers => 'No workers connected';

  @override
  String get workerOffline => 'Offline';

  @override
  String get workerOnline => 'Online';

  @override
  String get allSessions => 'All Sessions';

  @override
  String get noSessions => 'No sessions yet';

  @override
  String get sessionRenameTitle => 'Rename session';

  @override
  String get sessionNameLabel => 'Session name';

  @override
  String get terminateSession => 'Terminate Session';

  @override
  String get deleteSession => 'Delete Session';

  @override
  String deleteSessionConfirmTitle(Object name) {
    return 'Delete $name?';
  }

  @override
  String get deleteSessionConfirmBody =>
      'This removes the session record. The remote process is already stopped.';

  @override
  String terminateConfirmTitle(Object name) {
    return 'Terminate $name?';
  }

  @override
  String get terminateConfirmBody =>
      'This will stop the remote session and the running process.';

  @override
  String get terminate => 'Terminate';

  @override
  String get statusAttached => 'Running';

  @override
  String get statusDetachedGracePeriod => 'Running';

  @override
  String get statusRecovering => 'Recovering';

  @override
  String get statusExited => 'Ended';

  @override
  String get statusExpired => 'Ended';

  @override
  String get groupActive => 'ACTIVE';

  @override
  String get groupEnded => 'ENDED';

  @override
  String get sessionDetails => 'Session Details';

  @override
  String get sessionId => 'Session ID';

  @override
  String get agentKind => 'Agent';

  @override
  String get worker => 'Worker';

  @override
  String get createdAt => 'Created';

  @override
  String get lastActivity => 'Last activity';

  @override
  String get exitCode => 'Exit code';

  @override
  String get exitReason => 'Exit reason';

  @override
  String get sessions => 'Sessions';

  @override
  String get current => 'Current';

  @override
  String get selectSession => 'Select session';

  @override
  String get createSessionFailed => 'Failed to create session';

  @override
  String get chooseWorker => 'Choose worker';

  @override
  String get runtimeTerminal => 'Terminal';

  @override
  String get runtimeShell => 'Shell';

  @override
  String get runtimeShellHint =>
      'Run any CLI — Claude Code, Codex, and other agents are detected automatically.';

  @override
  String get connection => 'Connection';

  @override
  String get connectionState => 'Status';

  @override
  String get gateway => 'Gateway';

  @override
  String get latency => 'Latency';

  @override
  String get network => 'Network';

  @override
  String get networkWifi => 'Wi-Fi';

  @override
  String get networkMobile => 'Mobile data';

  @override
  String get networkEthernet => 'Ethernet';

  @override
  String get networkNone => 'No network';

  @override
  String get connLive => 'Connected';

  @override
  String get connConnecting => 'Connecting…';

  @override
  String get connReplaying => 'Restoring…';

  @override
  String get connReconnecting => 'Reconnecting…';

  @override
  String get connClosed => 'Disconnected';

  @override
  String get connExited => 'Ended';

  @override
  String get connError => 'Error';

  @override
  String get connIdle => 'Idle';

  @override
  String get gatewayConnected => 'Connected';

  @override
  String get gatewayDisconnected => 'Disconnected';

  @override
  String ms(int n) {
    return '$n ms';
  }

  @override
  String get more => 'More';

  @override
  String get files => 'Files';

  @override
  String get settings => 'Settings';

  @override
  String get reconnectBanner => 'Reconnecting…';

  @override
  String get connectBanner => 'Connecting…';

  @override
  String get restoringBanner => 'Restoring session…';

  @override
  String sessionEndedBanner(String reason) {
    return 'Session ended ($reason)';
  }

  @override
  String get sessionErrorBanner => 'Connection error';

  @override
  String get displacedBanner => 'Opened elsewhere — tap to reconnect';

  @override
  String get tapToReconnect => 'Tap to reconnect';

  @override
  String get account => 'Account';

  @override
  String get appearance => 'Appearance';

  @override
  String get terminal => 'Terminal';

  @override
  String get keyboardToolbar => 'Keyboard Toolbar';

  @override
  String get language => 'Language';

  @override
  String get security => 'Security';

  @override
  String get about => 'About';

  @override
  String get appearanceSystem => 'System';

  @override
  String get appearanceLight => 'Light';

  @override
  String get appearanceDark => 'Dark';

  @override
  String get terminalFontSize => 'Font size';

  @override
  String get languageSystem => 'System';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageChinese => '简体中文';

  @override
  String get changePassword => 'Change password';

  @override
  String get currentPassword => 'Current password';

  @override
  String get newPassword => 'New password';

  @override
  String get passwordChanged => 'Password changed';

  @override
  String get logout => 'Sign out';

  @override
  String get logoutConfirm => 'Sign out of Corterm?';

  @override
  String get appVersion => 'Version';

  @override
  String get gatewayVersion => 'Gateway version';

  @override
  String fontSizeFmt(double pt) {
    return '$pt pt';
  }

  @override
  String get legal => 'Legal & Policies';

  @override
  String legalVersionCaption(String date) {
    return 'Effective: $date';
  }

  @override
  String get legalIndexIntro =>
      'The following documents govern your use of Corterm. The Chinese version is authoritative.';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get privacyPolicyDesc => 'What we collect, how it is used and stored.';

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String get termsOfServiceDesc =>
      'Scope of the service, acceptable use, liability.';

  @override
  String get consentPrefix => 'I have read and agree to the ';

  @override
  String get consentAnd => ' and ';

  @override
  String get consentAlertTitle => 'Terms & Privacy';

  @override
  String get consentAlertBody =>
      'To protect your lawful rights and interests, please read and agree to the Terms of Service and Privacy Policy.';

  @override
  String get agree => 'Agree';

  @override
  String get disagree => 'Decline';

  @override
  String get deleteAccount => 'Delete Account';

  @override
  String get deleteAccountConfirmTitle => 'Delete this account?';

  @override
  String get deleteAccountConfirmBody =>
      'The account, its sessions and preferences will be permanently deleted on the server. This cannot be undone.';

  @override
  String get aboutTagline => 'Mobile AI Agent Workspace';

  @override
  String get filesTitle => 'Files';

  @override
  String get upload => 'Upload';

  @override
  String get uploadDone => 'Upload complete';

  @override
  String get uploadFailed => 'Upload failed';

  @override
  String get downloadFailed => 'Download failed';

  @override
  String get emptyFolder => 'Empty folder';

  @override
  String get listTruncated => 'Listing truncated (server limit reached).';

  @override
  String get workersTitle => 'Workers';

  @override
  String sessionCount(int n) {
    return '$n sessions';
  }

  @override
  String get workerHostname => 'Hostname';

  @override
  String get workerOs => 'OS';

  @override
  String get workerVersion => 'Worker version';

  @override
  String get upgrade => 'Upgrade';

  @override
  String get upgradeConfirm => 'Upgrade this worker now?';

  @override
  String get openSessions => 'Open Sessions';

  @override
  String get diagnostics => 'Diagnostics';

  @override
  String get gatewayReachable => 'Gateway reachability';

  @override
  String get diagnosticTesting => 'Testing…';

  @override
  String get diagnosticFail => 'Unreachable';

  @override
  String get platform => 'Device';

  @override
  String get keepScreenAwake => 'Keep screen awake';

  @override
  String get otherLoginMethods => 'Other sign-in methods';

  @override
  String oauthPending(String provider) {
    return 'Waiting for $provider…';
  }

  @override
  String oauthFailed(String provider) {
    return '$provider sign-in failed';
  }

  @override
  String get createSession => 'Create Session';

  @override
  String get creating => 'Creating…';

  @override
  String get selectWorker => 'Select worker';

  @override
  String get create => 'Create';

  @override
  String get saved => 'Saved';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get email => 'Email';

  @override
  String get tunnelTitle => 'Port Forwarding';

  @override
  String get tunnelPortLabel => 'Port';

  @override
  String get tunnelPortPlaceholder => '1-65535';

  @override
  String get tunnelEmpty => 'No tunnels yet';

  @override
  String tunnelExpires(String time) {
    return 'Expires $time';
  }

  @override
  String get tunnelCopyLink => 'Copy link';

  @override
  String get tunnelOpen => 'Open';

  @override
  String get tunnelRevoke => 'Revoke';

  @override
  String get tunnelInvalidPort => 'Port must be 1-65535';

  @override
  String get profileTitle => 'Profile';

  @override
  String get displayNameLabel => 'Display name';

  @override
  String get hasPassword => 'Password set';

  @override
  String get avatarUpdated => 'Avatar updated';

  @override
  String get activateTitle => 'Device activation';

  @override
  String get activateIntro =>
      'Enter the activation code shown by your device or CLI to authorize it with your account.';

  @override
  String get activateCodeLabel => 'Activation code';

  @override
  String get activateConfirm => 'Authorize';

  @override
  String get activateDone => 'Device authorized';

  @override
  String get activateInvalidCode => 'Invalid or expired code';

  @override
  String get deviceAccess => 'Device access';

  @override
  String get scrollbackQuota => 'Server scrollback';

  @override
  String get terminalSize => 'Terminal size';
}
