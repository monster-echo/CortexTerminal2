import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corterm_mobile/features/activate/activate_screen.dart';
import 'package:corterm_mobile/features/auth/presentation/login_screen.dart';
import 'package:corterm_mobile/features/auth/presentation/phone_login_screen.dart';
import 'package:corterm_mobile/features/home/home_shell.dart';
import 'package:corterm_mobile/features/workers/presentation/worker_select_screen.dart';
import 'package:corterm_mobile/features/search/search_screen.dart';
import 'package:corterm_mobile/features/workspaces/presentation/new_workspace_screen.dart';
import 'package:corterm_mobile/features/workspaces/presentation/folder_picker_screen.dart';
import 'package:corterm_mobile/features/workspaces/presentation/workspace_detail_screen.dart';
import 'package:corterm_mobile/features/workspaces/presentation/new_session_flow_screen.dart';
import 'package:corterm_mobile/features/workspaces/presentation/ungrouped_sessions_screen.dart';
import 'package:corterm_mobile/features/session/presentation/session_terminal_screen.dart';
import 'package:corterm_mobile/features/files/presentation/files_screen.dart';
import 'package:corterm_mobile/features/files/presentation/file_preview_screen.dart';
import 'package:corterm_mobile/features/tunnels/presentation/port_forwarding_screen.dart';
import 'package:corterm_mobile/features/computers/presentation/computers_screen.dart';
import 'package:corterm_mobile/features/computers/presentation/pair_computer_screen.dart';
import 'package:corterm_mobile/features/computers/presentation/computer_detail_screen.dart';
import 'package:corterm_mobile/features/membership/presentation/me_screen.dart';
import 'package:corterm_mobile/features/membership/presentation/membership_screen.dart';
import 'package:corterm_mobile/features/membership/presentation/redeem_screen.dart';
import 'package:corterm_mobile/features/membership/presentation/referral_screen.dart';
import 'package:corterm_mobile/features/settings/settings_screen.dart';
import 'package:corterm_mobile/features/settings/preferences_screen.dart';
import 'package:corterm_mobile/features/settings/security_screen.dart';
import 'package:corterm_mobile/features/settings/about_screen.dart';
import 'package:corterm_mobile/features/settings/terminal_themes_screen.dart';
import 'package:corterm_mobile/features/settings/terminal_theme_editor_screen.dart';
import 'package:corterm_mobile/features/profile/presentation/profile_screen.dart';
import 'package:corterm_mobile/features/support/presentation/support_screen.dart';
import 'package:corterm_mobile/features/feedback/presentation/feedback_screen.dart';
import 'package:corterm_mobile/features/diagnostics/diagnostics_screen.dart';
import 'package:corterm_mobile/features/legal/legal_screens.dart';
import 'package:corterm_mobile/core/legal/legal_documents.dart';

import 'pages/test_harness.dart';

// Route-complete layout regression. These are controlled fixtures, not live accounts.
const pages = <String, Widget>{
  'login': LoginScreen(),
  'phone': PhoneLoginScreen(),
  'home': HomeShell(),
  'worker-select': WorkerSelectScreen(),
  'search': SearchScreen(),
  'new-workspace': NewWorkspaceScreen(),
  'folder-picker': FolderPickerScreen(workerId: 'w1'),
  'workspace': WorkspaceDetailScreen(workspaceId: 'ws1'),
  'new-session': NewSessionFlowScreen(),
  'ungrouped': UngroupedSessionsScreen(),
  'terminal': SessionTerminalScreen(sessionId: 'sess-0001'),
  'files': FilesScreen(
    workspaceId: 'ws1',
    workspaceName: '主工作区',
    rootPath: '/root',
  ),
  'preview': FilePreviewScreen(
    workspaceId: 'ws1',
    path: 'README.md',
    name: 'README.md',
    sizeBytes: 1234,
  ),
  'tunnels': PortForwardingScreen(workspaceId: 'ws1'),
  'computers': ComputersScreen(),
  'activate': ActivateScreen(),
  'pair': PairComputerScreen(),
  'computer': ComputerDetailScreen(workerId: 'w1'),
  'me': MeScreen(),
  'settings': SettingsScreen(),
  'membership': MembershipScreen(),
  'profile': ProfileScreen(),
  'support': SupportScreen(),
  'feedback': FeedbackScreen(),
  'about': AboutScreen(),
  'diagnostics': DiagnosticsScreen(),
  'preferences': PreferencesScreen(),
  'themes': TerminalThemesScreen(),
  'theme-editor': TerminalThemeEditorScreen(),
  'security': SecurityScreen(),
  'redeem': RedeemScreen(),
  'referral': ReferralScreen(),
  'privacy': LegalDocumentScreen(document: zhPrivacyPolicy),
  'terms': LegalDocumentScreen(document: zhTermsOfService),
  'deletion': LegalDocumentScreen(document: zhAccountDeletion),
};
void main() {
  setUp(initPageTestFixtures);
  for (final scenario in [
    (
      name: 'phone',
      size: const Size(390, 844),
      scale: 1.0,
      dark: false,
      locale: const Locale('zh'),
    ),
    (
      name: 'duo-wide',
      size: const Size(951, 669),
      scale: 1.0,
      dark: true,
      locale: const Locale('en'),
    ),
    (
      name: 'compact-large-text',
      size: const Size(320, 568),
      scale: 1.6,
      dark: false,
      locale: const Locale('zh'),
    ),
  ]) {
    for (final entry in pages.entries) {
      testWidgets('${scenario.name}: ${entry.key}', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = scenario.size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final page = scenario.locale.languageCode == 'en'
            ? switch (entry.key) {
                'privacy' => const LegalDocumentScreen(
                  document: enPrivacyPolicy,
                ),
                'terms' => const LegalDocumentScreen(
                  document: enTermsOfService,
                ),
                'deletion' => const LegalDocumentScreen(
                  document: enAccountDeletion,
                ),
                _ => entry.value,
              }
            : entry.value;
        await tester.pumpWidget(
          await pageHarness(
            page,
            locale: scenario.locale,
            textScale: scenario.scale,
            dark: scenario.dark,
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester.takeException(),
          isNull,
          reason: '${scenario.name}: ${entry.key}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
