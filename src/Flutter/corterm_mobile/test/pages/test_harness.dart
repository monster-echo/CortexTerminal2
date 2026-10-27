/// 页面 smoke 测试共享 harness：注入假数据 provider，离线构建任意页面。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corterm_mobile/app/theme/corterm_theme.dart';
import 'package:corterm_mobile/core/auth/auth_controller.dart';
import 'package:corterm_mobile/core/auth/token_store.dart';
import 'package:corterm_mobile/core/config/app_config.dart';
import 'package:corterm_mobile/core/models/session.dart';
import 'package:corterm_mobile/core/models/worker.dart';
import 'package:corterm_mobile/core/models/workspace.dart';
import 'package:corterm_mobile/core/storage/app_preferences.dart';
import 'package:corterm_mobile/features/files/data/file_repository.dart';
import 'package:corterm_mobile/features/feedback/data/feedback_repository.dart';
import 'package:corterm_mobile/features/membership/data/membership_repository.dart';
import 'package:corterm_mobile/features/membership/data/store_purchase_controller.dart';
import 'package:corterm_mobile/features/profile/data/profile_repository.dart';
import 'package:corterm_mobile/features/profile/presentation/profile_screen.dart';
import 'package:corterm_mobile/features/session/session_controller.dart';
import 'package:corterm_mobile/features/sessions/data/session_repository.dart';
import 'package:corterm_mobile/features/sessions/data/sessions_providers.dart';
import 'package:corterm_mobile/features/settings/data/preferences_repository.dart';
import 'package:corterm_mobile/features/support/data/support_repository.dart';
import 'package:corterm_mobile/features/tunnels/data/tunnel_repository.dart';
import 'package:corterm_mobile/features/workers/data/workspace_repository.dart';
import 'package:corterm_mobile/features/workspaces/data/workspace_providers.dart';
import 'package:corterm_mobile/l10n/app_localizations.dart';

import '../fakes.dart';

class _HarnessTokenStore implements TokenStore {
  @override
  String? get token => 'fake-token';
  @override
  String? get username => 'tester';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 离线 SessionRepository：固定 worker / session / 网关信息。
class FakeSessionApiRepo implements SessionRepository {
  @override
  Future<List<SessionSummary>> list() async => [
    SessionSummary(
      sessionId: 'sess-0001',
      name: '构建会话',
      workerId: 'w1',
      workerName: 'Mac mini',
      status: SessionStatus.attached,
      createdAt: DateTime(2026, 1, 1),
      lastActivityAt: DateTime(2026, 1, 1, 12),
      workspaceId: 'ws1',
    ),
  ];

  @override
  Future<List<WorkerSummary>> workers() async => [
    const WorkerSummary(
      workerId: 'w1',
      name: 'Mac mini',
      hostname: 'mac-mini.local',
      isOnline: true,
      sessionCount: 1,
    ),
    const WorkerSummary(
      workerId: 'w2',
      name: 'Linux box',
      hostname: 'linux.local',
      isOnline: false,
      sessionCount: 0,
    ),
  ];

  @override
  Future<GatewayInfo> gatewayInfo() async =>
      const GatewayInfo(version: '1.2.3');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class FakeWorkspaceRepo implements WorkspaceRepository {
  @override
  Future<List<Workspace>> list() async => [
    const Workspace(
      workspaceId: 'ws1',
      workerId: 'w1',
      name: '主工作区',
      rootPath: '/root',
      isDefault: true,
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class FakeFeedbackRepo implements FeedbackRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) async =>
      throw UnimplementedError('${invocation.memberName}');
}

/// 默认假数据 overrides：页面用到哪个就生效哪个，多余的会被覆盖前 lazy 不执行。
Future<List<Override>> defaultOverrides() async {
  final mockPrefs = await SharedPreferences.getInstance();
  final prefs = AppPreferences(mockPrefs);
  return [
    sharedPreferencesProvider.overrideWithValue(mockPrefs),
    appConfigProvider.overrideWithValue('http://127.0.0.1:1'),
    authProvider.overrideWith((ref) {
      final controller = AuthController(_HarnessTokenStore());
      controller.state = const AuthState(
        status: AuthStatus.authenticated,
        username: 'tester',
      );
      return controller;
    }),
    workersProvider.overrideWith((ref) => FakeSessionApiRepo().workers()),
    sessionsProvider.overrideWith((ref) => FakeSessionApiRepo().list()),
    gatewayInfoProvider.overrideWith(
      (ref) async => const GatewayInfo(version: '1.2.3'),
    ),
    workspacesProvider.overrideWith((ref) => FakeWorkspaceRepo().list()),
    profileProvider.overrideWith(
      (ref) async => UserProfile(
        id: 'u1',
        username: 'tester',
        email: 'tester@example.com',
        displayName: 'tester',
        hasPassword: true,
      ),
    ),
    profileRepositoryProvider.overrideWith((ref) => FakeProfileRepo()),
    membershipStatusProvider.overrideWith(
      (ref) async => <String, dynamic>{'tier': 'free'},
    ),
    membershipPlansProvider.overrideWith(
      (ref) async => <Map<String, dynamic>>[
        <String, dynamic>{'id': 'pro', 'name': 'Pro'},
      ],
    ),
    membershipRepositoryProvider.overrideWith((ref) => FakeMembershipRepo()),
    referralSummaryProvider.overrideWith(
      (ref) => FakeMembershipRepo().referral(),
    ),
    storePurchaseProvider.overrideWith(
      (ref) => StorePurchaseController(ref, false),
    ),
    supportInfoProvider.overrideWith(
      (ref) async => SupportInfo(
        feishuGroup: SupportGroup(name: '飞书群', url: '', qrCodeUrl: ''),
      ),
    ),
    fileRepositoryProvider.overrideWith((ref) => FakeFileRepo()),
    tunnelRepositoryProvider.overrideWith((ref) => FakeTunnelRepo()),
    feedbackRepositoryProvider.overrideWith((ref) => FakeFeedbackRepo()),
    scrollbackPreferenceProvider.overrideWith(
      (ref) async =>
          ScrollbackPreference(maxBytes: 64000, maxAllowedBytes: 64000),
    ),
    sessionControllerProvider.overrideWith(
      (ref) => FakeSessionController(prefs),
    ),
  ];
}

/// 页面测试统一包裹：Riverpod overrides + GoRouter + ShadApp + 中文 l10n + 主题色扩展。
Future<Widget> pageHarness(
  Widget child, {
  List<Override> extra = const [],
  List<RouteBase> extraRoutes = const [],
  Locale locale = const Locale('zh'),
  double textScale = 1,
  bool dark = false,
}) async {
  pageChild = child;
  return ProviderScope(
    overrides: [...await defaultOverrides(), ...extra],
    child: ShadApp.router(
      locale: locale,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      materialThemeBuilder: (context, theme) => theme.copyWith(
        extensions: [dark ? CortermColors.dark : CortermColors.light],
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (_, _) => NoTransitionPage(child: pageChild),
          ),
          ...extraRoutes,
        ],
      ),
    ),
  );
}

Widget pageChild = const SizedBox();

/// 统一初始化：mock SharedPreferences 与 PackageInfo。
Future<void> initPageTestFixtures() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  PackageInfo.setMockInitialValues(
    appName: 'CortexTerminal',
    packageName: 'com.example.corterm',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
}

/// pump 页面并让 FutureProvider 数据落地（两段定时 pump，兼容 fake async）。
Future<void> settlePage(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(await pageHarness(child));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}
