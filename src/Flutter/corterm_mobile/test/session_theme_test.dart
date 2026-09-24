import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

import 'package:corterm_mobile/app/theme/corterm_theme.dart';
import 'package:corterm_mobile/app/theme/terminal_theme.dart';
import 'package:corterm_mobile/core/models/session.dart';
import 'package:corterm_mobile/core/storage/app_preferences.dart';
import 'package:corterm_mobile/core/ws/terminal_socket.dart';
import 'package:corterm_mobile/core/ws/ws_frames.dart';
import 'package:corterm_mobile/features/sessions/data/session_repository.dart';
import 'package:corterm_mobile/features/sessions/data/sessions_providers.dart';
import 'package:corterm_mobile/features/session/presentation/session_terminal_screen.dart';
import 'package:corterm_mobile/features/session/presentation/terminal_keyboard_toolbar.dart';
import 'package:corterm_mobile/features/session/session_controller.dart';
import 'package:corterm_mobile/features/session/session_state.dart';

/// 测试不建真连：socket 工厂返回空帧流假 socket。
class _FakeSocket implements TerminalSocket {
  @override
  Stream<ServerFrame> get frames => const Stream.empty();

  @override
  bool get closedByUs => false;

  @override
  bool get detachedByUs => false;

  @override
  bool get sessionNotFound => false;

  @override
  void forceClose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _TestSessionController extends SessionController {
  _TestSessionController(AppPreferences prefs)
      : super(
          _NoopRepo(),
          ({required String sessionId, int sinceSeq = 0}) async =>
              _FakeSocket(),
          prefs,
        );

  void seed(SessionState state) => this.state = state;
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

  /// Light App Context 全局浅色 —— Session 页必须依旧深色（design/00 §4）。
  Widget harness(
    SessionController controller, {
    double keyboardInset = 0,
  }) {
    final router = GoRouter(
      initialLocation: '/s',
      routes: [
        GoRoute(
          path: '/s',
          builder: (_, _) => const SessionTerminalScreen(sessionId: 's1'),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        sessionControllerProvider.overrideWith((ref) => controller),
        sessionsProvider.overrideWith((ref) async => [_session()]),
      ],
      child: MaterialApp.router(
        theme: ThemeData(
          useMaterial3: true,
          extensions: const [CortermColors.light],
        ),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(viewInsets: EdgeInsets.only(bottom: keyboardInset)),
          child: child!,
        ),
      ),
    );
  }

  SessionController controllerWithSession() {
    final entry = SessionTerminalState(
      terminal: Terminal(maxLines: 200),
      epoch: 0,
      connState: TerminalConnState.live,
      rttMs: 12,
      workerId: 'w1',
    );
    final controller = _TestSessionController(appPreferences);
    controller.seed(
      SessionState(
        currentSessionId: 's1',
        openedSessionIds: const ['s1'],
        entries: {'s1': entry},
      ),
    );
    return controller;
  }

  testWidgets('软键盘弹出时键盘工具栏出现在键盘上方（design/04 §3）', (tester) async {
    tester.view.physicalSize = _phone * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final controller = controllerWithSession();

    await tester.pumpWidget(harness(controller, keyboardInset: _keyboardInset));
    await tester.pump(const Duration(milliseconds: 200));

    final toolbar = find.byType(TerminalKeyboardToolbar);
    expect(toolbar, findsOneWidget);

    final rect = tester.getRect(toolbar);
    expect(rect.height, TerminalKeyboardToolbar.height);
    // 工具栏悬浮在键盘正上方（overlay，不挤占终端区）。
    expect(rect.bottom, _phone.height - _keyboardInset);
    expect(rect.top, greaterThanOrEqualTo(0));
    // 终端区贴到键盘顶边。
    expect(
      tester.getRect(find.byType(TerminalView)).bottom,
      _phone.height - _keyboardInset,
    );
  });

  testWidgets('无软键盘时工具栏收起，终端占满（design/04 §2）', (tester) async {
    tester.view.physicalSize = _phone * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final controller = controllerWithSession();

    await tester.pumpWidget(harness(controller));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(TerminalKeyboardToolbar), findsNothing);
    expect(tester.getRect(find.byType(TerminalView)).bottom, _phone.height);
  });

  testWidgets('Session 页固定 Dark Tool Context：深色 Scaffold + 深色终端配色', (tester) async {
    tester.view.physicalSize = _phone * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final controller = controllerWithSession();

    await tester.pumpWidget(harness(controller));
    await tester.pump(const Duration(milliseconds: 200));

    final context = tester.element(find.byType(TerminalView));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(Theme.of(context).scaffoldBackgroundColor,
        CortermColors.darkTool.background);

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.theme.background, cortermTerminalDarkTheme.background);
  });
}
