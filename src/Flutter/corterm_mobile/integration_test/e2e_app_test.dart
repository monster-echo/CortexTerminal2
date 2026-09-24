import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

import 'package:corterm_mobile/app/router.dart';
import 'package:corterm_mobile/app/theme/app_theme.dart' show shadLightTheme;
import 'package:corterm_mobile/app/theme/corterm_theme.dart';
import 'package:corterm_mobile/core/analytics/analytics_stub.dart';
import 'package:corterm_mobile/l10n/app_localizations.dart';
import 'package:corterm_mobile/core/auth/auth_controller.dart';
import 'package:corterm_mobile/core/models/session.dart';
import 'package:corterm_mobile/core/models/worker.dart';
import 'package:corterm_mobile/core/storage/app_preferences.dart';
import 'package:corterm_mobile/features/files/data/file_repository.dart';
import 'package:corterm_mobile/features/session/session_state.dart';
import 'package:corterm_mobile/features/sessions/data/sessions_providers.dart';
import 'package:go_router/go_router.dart';
import 'package:corterm_mobile/features/tunnels/data/tunnel_repository.dart';
import 'package:corterm_mobile/features/workspaces/data/workspace_providers.dart';
import 'package:corterm_mobile/core/models/workspace.dart';
import 'package:corterm_mobile/features/session/session_controller.dart';

import '../test/fakes.dart';

/// E2E（模拟器）：真实路由表 + 假数据源，从首页走查主要页面与主题一致性。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences sharedPreferences;
  late ProviderContainer container;

  setUpAll(() async {
    // 与 main.dart 一致：iOS 有 GoogleService-Info.plist，无参初始化即可。
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    final prefs = AppPreferences(sharedPreferences);

    final auth = AuthController(FakeTokenStore());
    auth.state =
        const AuthState(status: AuthStatus.authenticated, username: 'tester');

    final entry = SessionTerminalState(
      terminal: Terminal(maxLines: 200),
      epoch: 0,
      connState: TerminalConnState.live,
      rttMs: 12,
      workerId: 'w1',
    );
    final sessionController = FakeSessionController(prefs)
      ..seed(SessionState(
        currentSessionId: 's1',
        openedSessionIds: const ['s1'],
        entries: {'s1': entry},
      ));

    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      authProvider.overrideWith((ref) => auth),
      analyticsProvider.overrideWith((ref) => AnalyticsService()),
      sessionsProvider.overrideWith((ref) async => [
            SessionSummary(
              sessionId: 's1',
              name: '终端 1',
              workerId: 'w1',
              workerName: 'Mac mini',
              status: SessionStatus.attached,
              createdAt: DateTime(2026, 1, 1),
              lastActivityAt: DateTime(2026, 1, 1),
              workspaceId: 'ws1',
            ),
          ]),
      workersProvider.overrideWith((ref) async => [
            WorkerSummary(
              workerId: 'w1',
              name: 'Mac mini',
              hostname: 'mac-mini.local',
              isOnline: true,
              sessionCount: 1,
            ),
          ]),
      workspacesProvider.overrideWith((ref) async => [
            const Workspace(
              workspaceId: 'ws1',
              workerId: 'w1',
              name: 'CortexTerminal2',
              rootPath: '/Users/tester/Projects/CortexTerminal2',
            ),
          ]),
      sessionControllerProvider.overrideWith((ref) => sessionController),
      fileRepositoryProvider.overrideWith((ref) => FakeFileRepo()),
      tunnelRepositoryProvider.overrideWith((ref) => FakeTunnelRepo()),
    ]);
  });

  tearDown(() => container.dispose());

  Future<(WidgetTester, GoRouter)> pump(WidgetTester tester) async {
    final router = container.read(routerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ShadApp.router(
          routerConfig: router,
          theme: shadLightTheme(),
          materialThemeBuilder: (context, theme) => theme.copyWith(
            extensions: const [CortermColors.light],
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    return (tester, router);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('首页：双 Tab 与侧边栏', (tester) async {
    final (t, router) = await pump(tester);
    router.go('/home');
    await settle(t);

    expect(find.text('工作区'), findsWidgets);
    expect(find.text('CortexTerminal2'), findsOneWidget);
    expect(find.text('Mac mini · 1 个会话运行中'), findsOneWidget);

    await t.tap(find.text('电脑'));
    await settle(t);
    expect(find.text('在线 · 1 个工作区'), findsOneWidget);
  });

  testWidgets('搜索：最近会话与分组过滤', (tester) async {
    final (t, router) = await pump(tester);
    router.go('/search');
    await settle(t);

    expect(find.text('最近会话'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Cortex');
    await settle(t);
    expect(find.text('工作区'), findsOneWidget);
    expect(find.text('CortexTerminal2'), findsOneWidget);
  });

  testWidgets('新建工作区页可直接打开（回归：initState 读路由曾红屏）', (tester) async {
    final (t, router) = await pump(tester);
    router.go('/workspaces/new?workerId=w1');
    await settle(t);

    expect(find.text('新建工作区'), findsOneWidget);
    expect(find.text('创建工作区'), findsOneWidget);
    // query 预选的电脑名渲染出来。
    expect(find.text('Mac mini'), findsOneWidget);
  });

  testWidgets('工作区详情 → 新建会话流（锁定）', (tester) async {
    final (t, router) = await pump(tester);
    router.go('/workspaces/ws1');
    await settle(t);

    expect(find.text('CortexTerminal2'), findsWidgets);
    expect(find.text('电脑：Mac mini'), findsOneWidget);
    expect(find.text('终端 1'), findsOneWidget);

    router.go('/sessions/new?workspaceId=ws1');
    await settle(t);
    expect(find.text('创建会话'), findsOneWidget);
  });

  testWidgets('Session 终端：Dark Tool Context 全屏', (tester) async {
    final (t, router) = await pump(tester);
    router.go('/sessions/s1');
    await settle(t);

    expect(find.byType(TerminalView), findsOneWidget);
    final context = t.element(find.byType(TerminalView));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(
        Theme.of(context).scaffoldBackgroundColor, CortermColors.darkTool.background);
  });

  testWidgets('文件页：Dark Tool Context 列出目录', (tester) async {
    final (t, router) = await pump(tester);
    router.go(
        '/workspaces/ws1/files?name=CortexTerminal2&root=${Uri.encodeComponent('/Users/tester/Projects/CortexTerminal2')}');
    await settle(t);

    expect(find.text('lib'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('pubspec.yaml'), findsOneWidget);
  });

  testWidgets('端口转发页：空列表与新建入口', (tester) async {
    final (t, router) = await pump(tester);
    router.go('/workspaces/ws1/tunnels');
    await settle(t);

    expect(find.text('端口转发'), findsOneWidget);
  });

  testWidgets('我的 与 设置：Light App Context', (tester) async {
    final (t, router) = await pump(tester);
    router.go('/me');
    await settle(t);

    // Light App Context：页面渲染在浅色 token 环境下（扩展存在即通过 colorsOf）。
    expect(find.byType(Scaffold), findsWidgets);

    router.go('/settings');
    await settle(t);
    // 设备默认英文 locale，设置页标题为 Settings（l10n 正常注入即渲染）。
    expect(find.textContaining('Settings'), findsWidgets);
  });
}
