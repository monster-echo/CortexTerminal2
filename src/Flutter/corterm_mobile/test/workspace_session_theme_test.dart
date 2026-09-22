import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

import 'package:corterm_mobile/app/theme/app_theme.dart';
import 'package:corterm_mobile/app/theme/terminal_theme.dart';
import 'package:corterm_mobile/core/models/session.dart';
import 'package:corterm_mobile/core/storage/app_preferences.dart';
import 'package:corterm_mobile/features/sessions/data/session_repository.dart';
import 'package:corterm_mobile/features/sessions/data/sessions_providers.dart';
import 'package:corterm_mobile/features/workspace/widgets/more_actions_sheet.dart';
import 'package:corterm_mobile/features/workspace/widgets/terminal_toolbar.dart';
import 'package:corterm_mobile/features/workspace/workspace_controller.dart';
import 'package:corterm_mobile/features/workspace/workspace_screen.dart';
import 'package:corterm_mobile/features/workspace/workspace_state.dart';
import 'package:corterm_mobile/l10n/app_localizations.dart';

/// 测试不建连：直接注入 state（socket 工厂只兜 AssertionError）。
class _TestWorkspaceController extends WorkspaceController {
  _TestWorkspaceController(AppPreferences prefs)
      : super(
          _NoopRepo(),
          ({required String sessionId, int sinceSeq = 0}) async =>
              throw UnimplementedError('测试直接注入 state，不建立连接'),
          prefs,
        );

  void seed(WorkspaceState state) => this.state = state;
}

/// workspace 控制器只用到 rememberCurrent；其余调用视为测试漏了注入。
class _NoopRepo implements SessionRepository {
  @override
  Future<void> rememberCurrent(String? sessionId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// 手机竖屏视口（iPhone 18 Pro 逻辑尺寸）。
const _phone = Size(402, 874);

const _keyboardInset = 300.0;

SessionSummary _session() => SessionSummary(
      sessionId: 's1',
      name: 'demo',
      workerId: 'w1',
      workerName: 'tengxun-2',
      status: SessionStatus.attached,
      createdAt: DateTime(2026, 1, 1),
      lastActivityAt: DateTime(2026, 1, 1),
    );

void main() {
  late SharedPreferences sharedPreferences;
  late AppPreferences appPreferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
    appPreferences = AppPreferences(sharedPreferences);
  });

  /// App 主题固定浅色 —— Session 页必须依旧深色（§2/§3）。
  Widget harness(
    WorkspaceController controller, {
    double keyboardInset = 0,
  }) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        workspaceControllerProvider.overrideWith((ref) => controller),
        sessionsProvider.overrideWith((ref) async => [_session()]),
      ],
      child: ShadApp(
        theme: shadLightTheme(),
        darkTheme: shadDarkTheme(),
        themeMode: ThemeMode.light,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('zh')],
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(viewInsets: EdgeInsets.only(bottom: keyboardInset)),
          child: child!,
        ),
        home: const WorkspaceScreen(),
      ),
    );
  }

  WorkspaceController controllerWithLiveSession() {
    final entry = SessionTerminalState(
      terminal: Terminal(maxLines: 200),
      epoch: 0,
      connState: TerminalConnState.live,
      rttMs: 12,
      workerId: 'w1',
    );
    final controller = _TestWorkspaceController(appPreferences);
    controller.seed(
      WorkspaceState(
        currentSessionId: 's1',
        openedSessionIds: const ['s1'],
        entries: {'s1': entry},
      ),
    );
    return controller;
  }

  testWidgets('软键盘弹出时键盘工具栏出现在键盘上方（不再被键盘遮住）', (tester) async {
    tester.view.physicalSize = _phone * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final controller = controllerWithLiveSession();

    await tester.pumpWidget(harness(controller, keyboardInset: _keyboardInset));
    await tester.pumpAndSettle();

    final toolbar = find.byType(TerminalToolbar);
    expect(toolbar, findsOneWidget);

    final rect = tester.getRect(toolbar);
    expect(rect.height, TerminalToolbar.height);
    // 键盘顶边 = 视口高 - viewInsets.bottom；工具栏必须整体在其上方。
    expect(rect.bottom, lessThanOrEqualTo(_phone.height - _keyboardInset));
    expect(rect.top, greaterThanOrEqualTo(0));
    // 终端区被工具栏挤到键盘正上方。
    expect(
      tester.getRect(find.byType(TerminalView)).bottom,
      _phone.height - _keyboardInset - TerminalToolbar.height,
    );
  });

  testWidgets('无软键盘时工具栏收起，终端占满', (tester) async {
    tester.view.physicalSize = _phone * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final controller = controllerWithLiveSession();

    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    // heightFactor 0：工具栏折叠为 0 高，终端区直接贴到视口底部。
    expect(find.byType(TerminalToolbar), findsOneWidget);
    expect(tester.getRect(find.byType(TerminalView)).bottom, _phone.height);
  });

  testWidgets('App 浅色时 Session 页面跟随浅色（页面 + 右上角弹出的功能页）', (tester) async {
    tester.view.physicalSize = _phone * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final controller = controllerWithLiveSession();

    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    final pageContext = tester.element(find.byType(TerminalToolbar));
    expect(ShadTheme.of(pageContext).brightness, Brightness.light);
    expect(Theme.of(pageContext).brightness, Brightness.light);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, shadLightTheme().colorScheme.background);

    // 右上角 ⋯ → More Actions sheet 同样跟随浅色（sheet 走独立路由，
    // 但主题来自 ShadApp 的 themeMode，无需再单独强制）。
    await tester.tap(find.byIcon(LucideIcons.ellipsis));
    await tester.pumpAndSettle();

    expect(find.byType(MoreActionsSheet), findsOneWidget);
    final sheetContext = tester.element(find.byType(MoreActionsSheet));
    expect(ShadTheme.of(sheetContext).brightness, Brightness.light);
    expect(Theme.of(sheetContext).brightness, Brightness.light);
  });

  testWidgets('终端主题 system 模式跟随 App：浅色 App 下终端用浅色配色', (tester) async {
    tester.view.physicalSize = _phone * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final controller = controllerWithLiveSession();

    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    // resolveTerminalTheme 每次按档案新建实例，按值断言背景色。
    expect(
      view.theme.background,
      cortermTerminalLightTheme.background,
    );
  });

  testWidgets('终端主题固定 dark：浅色 App 下终端仍是深色配色', (tester) async {
    tester.view.physicalSize = _phone * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await appPreferences.setTerminalThemeMode('dark');
    final controller = controllerWithLiveSession();

    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(
      view.theme.background,
      cortermTerminalDarkTheme.background,
    );
  });
}