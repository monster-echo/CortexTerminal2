import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

import 'package:corterm_mobile/app/router.dart';
import 'package:corterm_mobile/core/api/api_client.dart';
import 'package:corterm_mobile/app/theme/terminal_theme.dart';
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

import 'package:corterm_mobile/features/membership/data/membership_repository.dart';
import 'package:corterm_mobile/features/profile/data/profile_repository.dart';
import 'package:corterm_mobile/features/support/data/support_repository.dart';

import '../test/fakes.dart';

/// E2E（模拟器）：真实路由表 + 假数据源，从首页走查主要页面与主题一致性。
class _IntegrationApi implements ApiClient {
  @override
  Future<Map<String, dynamic>> getMap(
    String path, {
    Map<String, dynamic>? query,
  }) async => switch (path) {
    '/api/billing/subscription' => {'tier': 'free', 'expiresAtUtc': null},
    '/api/iap/catalog' => {'available': false, 'products': <dynamic>[]},
    _ => throw StateError('Unexpected integration API request: $path'),
  };

  @override
  Future<List<dynamic>> getList(String path) async {
    if (path == '/api/billing/plans') return [];
    throw StateError('Unexpected integration API request: $path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected integration API call: ${invocation.memberName}',
  );
}

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
    auth.state = const AuthState(
      status: AuthStatus.authenticated,
      username: 'tester',
    );

    final entry = SessionTerminalState(
      terminal: Terminal(maxLines: 200),
      epoch: 0,
      connState: TerminalConnState.live,
      rttMs: 12,
      workerId: 'w1',
    );
    final sessionController = FakeSessionController(prefs)
      ..seed(
        SessionState(
          currentSessionId: 's1',
          openedSessionIds: const ['s1'],
          entries: {'s1': entry},
        ),
      );

    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        apiClientProvider.overrideWithValue(_IntegrationApi()),
        authProvider.overrideWith((ref) => auth),
        analyticsProvider.overrideWith((ref) => AnalyticsService()),
        sessionsProvider.overrideWith(
          (ref) async => [
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
          ],
        ),
        workersProvider.overrideWith(
          (ref) async => [
            WorkerSummary(
              workerId: 'w1',
              name: 'Mac mini',
              hostname: 'mac-mini.local',
              isOnline: true,
              sessionCount: 1,
            ),
          ],
        ),
        workspacesProvider.overrideWith(
          (ref) async => [
            const Workspace(
              workspaceId: 'ws1',
              workerId: 'w1',
              name: 'CortexTerminal2',
              rootPath: '/Users/tester/Projects/CortexTerminal2',
            ),
          ],
        ),
        sessionControllerProvider.overrideWith((ref) => sessionController),
        fileRepositoryProvider.overrideWith((ref) => FakeFileRepo()),
        profileRepositoryProvider.overrideWith((ref) => FakeProfileRepo()),
        supportRepositoryProvider.overrideWith((ref) => FakeSupportRepo()),
        membershipRepositoryProvider.overrideWith(
          (ref) => FakeMembershipRepo(),
        ),
        tunnelRepositoryProvider.overrideWith((ref) => FakeTunnelRepo()),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<(WidgetTester, GoRouter)> pump(WidgetTester tester) async {
    final router = container.read(routerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ShadApp.router(
          routerConfig: router,
          locale: const Locale('zh'),
          theme: shadLightTheme(),
          materialThemeBuilder: (context, theme) =>
              theme.copyWith(extensions: const [CortermColors.light]),
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

  testWidgets('首页工作区与侧边栏电脑入口', (tester) async {
    final (t, router) = await pump(tester);
    router.go('/home');
    await settle(t);

    expect(find.text('工作区'), findsWidgets);
    expect(find.text('CortexTerminal2'), findsOneWidget);
    expect(find.textContaining('Mac mini'), findsWidgets);

    final scaffold = t.state<ScaffoldState>(find.byType(Scaffold).first);
    scaffold.openDrawer();
    await settle(t);
    expect(find.text('电脑'), findsOneWidget);
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

    expect(find.text('创建工作区'), findsWidgets);
    // query 预选的电脑名渲染出来。
    expect(find.text('Mac mini'), findsOneWidget);
  });

  testWidgets('工作区详情 → 新建会话流（锁定）', (tester) async {
    final (t, router) = await pump(tester);
    router.go('/workspaces/ws1');
    await settle(t);

    expect(find.text('CortexTerminal2'), findsWidgets);
    expect(find.textContaining('Mac mini'), findsWidgets);
    expect(find.text('终端 1'), findsOneWidget);

    router.go('/sessions/new?workspaceId=ws1');
    await settle(t);
    expect(find.text('创建会话'), findsOneWidget);
  });

  testWidgets('Session 终端：默认跟随浅色应用', (tester) async {
    final (t, router) = await pump(tester);
    router.go('/sessions/s1');
    await settle(t);

    expect(find.byType(TerminalView), findsOneWidget);
    final context = t.element(find.byType(TerminalView));
    expect(Theme.of(context).brightness, Brightness.light);
    expect(
      Theme.of(context).scaffoldBackgroundColor,
      cortermTerminalLightTheme.background,
    );
  });

  testWidgets('浅色 App 自定义深色终端 → 跟随应用恢复浅色', (tester) async {
    await container
        .read(terminalThemeSelectionProvider.notifier)
        .set('default-dark');
    final (t, router) = await pump(tester);
    router.go('/sessions/s1');
    await settle(t);
    expect(
      Theme.of(t.element(find.byType(TerminalView))).brightness,
      Brightness.dark,
    );
    expect(
      Theme.of(t.element(find.byType(TerminalView))).scaffoldBackgroundColor,
      cortermTerminalDarkTheme.background,
    );
    await container
        .read(terminalThemeSelectionProvider.notifier)
        .set('followApp');
    await settle(t);
    expect(
      Theme.of(t.element(find.byType(TerminalView))).brightness,
      Brightness.light,
    );
  });

  testWidgets('工作区 → Session → 返回保留工作区页面', (tester) async {
    final (t, router) = await pump(tester);
    router.go('/home');
    await settle(t);
    await t.tap(find.text('CortexTerminal2'));
    await settle(t);
    await t.tap(find.text('终端 1'));
    await settle(t);
    expect(find.byType(TerminalView), findsOneWidget);
    router.pop();
    await settle(t);
    expect(find.textContaining('Mac mini'), findsWidgets);
    expect(find.text('终端 1'), findsOneWidget);
    expect(find.byType(TerminalView), findsNothing);
  });

  testWidgets('文件页：Dark Tool Context 列出目录', (tester) async {
    final (t, router) = await pump(tester);
    router.go(
      '/workspaces/ws1/files?name=CortexTerminal2&root=${Uri.encodeComponent('/Users/tester/Projects/CortexTerminal2')}',
    );
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

  testWidgets('剩余路由逐条直达：任何页面启动即崩都逃不过', (tester) async {
    final (t, router) = await pump(tester);

    const routes = <String, Matcher>{
      '/computers': findsOneWidget,
      '/computers/new': findsOneWidget,
      '/computers/w1': findsOneWidget,
      '/folder-picker?workerId=w1': findsOneWidget,
      '/workspaces/new': findsOneWidget,
      '/sessions/new': findsOneWidget,
      '/workspaces/ws1/files/preview?path=README.md&name=README.md&size=1234':
          findsOneWidget,
      '/settings': findsOneWidget,
      '/settings/membership': findsOneWidget,
      '/workers/select': findsOneWidget,
      '/sessions/ungrouped': findsOneWidget,
      '/legal/terms': findsOneWidget,
      '/legal/deletion': findsOneWidget,
      '/settings/profile': findsOneWidget,
      '/settings/support': findsOneWidget,
      '/settings/feedback': findsOneWidget,
      '/settings/about': findsOneWidget,
      '/settings/preferences': findsOneWidget,
      '/settings/terminal-themes': findsOneWidget,
      '/settings/terminal-themes/edit': findsOneWidget,
      '/settings/security': findsOneWidget,
      '/settings/redeem': findsOneWidget,
      '/settings/referral': findsOneWidget,
      '/legal/privacy': findsOneWidget,
      '/activate': findsOneWidget,
    };

    for (final entry in routes.entries) {
      router.go(entry.key);
      // 每个页面给足渲染时间；异常会在 pump 阶段被测试框架捕获。
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 400));
      expect(
        t.takeException(),
        isNull,
        reason: 'route ${entry.key} threw during build',
      );
      expect(
        find.byType(Scaffold),
        findsWidgets,
        reason: 'route ${entry.key} did not render a scaffold',
      );
    }
  });

  testWidgets('会员目录不可用时隐藏购买，并提供重试和恢复入口', (tester) async {
    final (t, router) = await pump(tester);
    router.go('/settings/membership');
    await settle(t);
    expect(find.text('当前为免费账户'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('恢复购买'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    await t.tap(find.text('重试'));
    await settle(t);
    expect(find.text('重试'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Session 左滑删除取消后保留列表', (tester) async {
    final (t, router) = await pump(tester);
    router.go('/workspaces/ws1');
    await settle(t);
    await t.drag(find.text('终端 1'), const Offset(-400, 0));
    await t.pump(const Duration(milliseconds: 500));
    // ArkTS pattern: swipe reveals the action; deletion only starts after tapping it.
    await t.tap(find.text('删除').last);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsOneWidget);
    await t.tap(find.text('取消'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('终端 1'), findsOneWidget);
  });

  testWidgets('我的 与 设置：Light App Context', (tester) async {
    final (t, router) = await pump(tester);
    router.go('/me');
    await settle(t);

    // Light App Context：页面渲染在浅色 token 环境下（扩展存在即通过 colorsOf）。
    expect(find.byType(Scaffold), findsWidgets);

    router.go('/settings');
    await settle(t);
    // 固定中文 locale，避免测试依赖模拟器系统语言。
    expect(find.text('设置'), findsWidgets);
  });
}
