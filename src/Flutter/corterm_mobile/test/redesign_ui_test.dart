import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corterm_mobile/app/theme/corterm_theme.dart';
import 'package:corterm_mobile/core/models/session.dart';
import 'package:corterm_mobile/core/models/worker.dart';
import 'package:corterm_mobile/core/models/workspace.dart';
import 'package:corterm_mobile/features/home/home_shell.dart';
import 'package:corterm_mobile/features/search/search_screen.dart';
import 'package:corterm_mobile/features/sessions/data/session_repository.dart';
import 'package:corterm_mobile/features/sessions/data/sessions_providers.dart';
import 'package:corterm_mobile/features/workspaces/data/workspace_providers.dart';
import 'package:corterm_mobile/features/workspaces/presentation/workspace_detail_screen.dart';
import 'package:corterm_mobile/l10n/app_localizations.dart';
import 'package:corterm_mobile/core/storage/app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:corterm_mobile/core/auth/auth_controller.dart';
import 'package:corterm_mobile/features/profile/data/profile_repository.dart';
import 'package:corterm_mobile/features/membership/data/store_purchase_controller.dart';

import 'fakes.dart';

Workspace _ws(String id, String name, String workerId) => Workspace(
  workspaceId: id,
  workerId: workerId,
  name: name,
  rootPath: '~/Projects/$name',
);

WorkerSummary _worker(String id, String name, {bool online = true}) =>
    WorkerSummary(
      workerId: id,
      name: name,
      hostname: '$id.local',
      isOnline: online,
      sessionCount: 0,
    );

SessionSummary _session(
  String id,
  String name,
  String workspaceId, {
  bool running = true,
}) => SessionSummary(
  sessionId: id,
  name: name,
  workerId: 'w1',
  workerName: 'Mac mini',
  status: running ? SessionStatus.attached : SessionStatus.exited,
  createdAt: DateTime(2026, 1, 1),
  lastActivityAt: DateTime(2026, 1, 1),
  workspaceId: workspaceId,
);

class _FakeSessionRepo implements SessionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

late SharedPreferences _sharedPreferences;

Widget _harness({
  required List<Workspace> workspaces,
  required List<WorkerSummary> workers,
  required List<SessionSummary> sessions,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(_sharedPreferences),
      authProvider.overrideWith((ref) {
        final auth = AuthController(FakeTokenStore());
        auth.state = const AuthState(
          status: AuthStatus.authenticated,
          username: 'tester',
        );
        return auth;
      }),
      profileRepositoryProvider.overrideWith((ref) => FakeProfileRepo()),
      membershipStatusProvider.overrideWith((ref) async => {'tier': 'free'}),
      workspacesProvider.overrideWith((ref) async => workspaces),
      workersProvider.overrideWith((ref) async => workers),
      sessionsProvider.overrideWith((ref) async => sessions),
      workspaceSessionsProvider.overrideWith(
        (ref, workspaceId) =>
            sessions.where((s) => s.workspaceId == workspaceId).toList(),
      ),
      sessionRepositoryProvider.overrideWith((ref) => _FakeSessionRepo()),
    ],
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        extensions: const [CortermColors.light],
      ),
      home: child,
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _sharedPreferences = await SharedPreferences.getInstance();
  });
  testWidgets('首页展示工作区及所属电脑', (tester) async {
    await tester.pumpWidget(
      _harness(
        workspaces: [_ws('ws1', 'CortexTerminal2', 'w1')],
        workers: [_worker('w1', 'Mac mini')],
        sessions: [_session('s1', '终端 1', 'ws1')],
        child: const HomeShell(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('CortexTerminal2'), findsOneWidget);
    expect(find.textContaining('Mac mini'), findsWidgets);
  });

  testWidgets('首页继续会话只展示在线电脑的存活会话', (tester) async {
    await tester.pumpWidget(
      _harness(
        workspaces: [_ws('ws1', '项目', 'w1')],
        workers: [_worker('w1', 'Mac mini', online: false)],
        sessions: [_session('s1', '离线会话', 'ws1')],
        child: const HomeShell(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('继续会话'), findsNothing);
    expect(find.text('离线会话'), findsNothing);
  });

  testWidgets('首页继续会话不展示已结束的会话', (tester) async {
    await tester.pumpWidget(
      _harness(
        workspaces: [_ws('ws1', '项目', 'w1')],
        workers: [_worker('w1', 'Mac mini')],
        sessions: [
          _session('s1', '运行中的会话', 'ws1'),
          _session('s2', '已结束的会话', 'ws1', running: false),
        ],
        child: const HomeShell(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('继续会话'), findsOneWidget);
    expect(find.text('运行中的会话'), findsOneWidget);
    expect(find.text('已结束的会话'), findsNothing);
  });

  testWidgets('首页侧边栏提供电脑入口', (tester) async {
    await tester.pumpWidget(
      _harness(
        workspaces: [_ws('ws1', 'CortexTerminal2', 'w1')],
        workers: [_worker('w1', 'Mac mini')],
        sessions: const [],
        child: const HomeShell(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    scaffold.openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('电脑'), findsOneWidget);
  });

  testWidgets('侧边栏：首个工作区默认展开显示会话，底部有新建与头像（design/01 §4）', (tester) async {
    final key = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      _harness(
        workspaces: [_ws('ws1', 'CortexTerminal2', 'w1')],
        workers: [_worker('w1', 'Mac mini')],
        sessions: [_session('s1', '终端 1', 'ws1')],
        child: Scaffold(
          key: key,
          drawer: const CortermSidebar(),
          body: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    key.currentState!.openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('云枢终端'), findsOneWidget);
    expect(find.text('CortexTerminal2'), findsOneWidget);
    expect(find.text('电脑'), findsOneWidget);
  });

  testWidgets('侧边栏在选中工作区内提供新建会话入口', (tester) async {
    final key = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      _harness(
        workspaces: [_ws('ws1', 'CortexTerminal2', 'w1')],
        workers: [_worker('w1', 'Mac mini')],
        sessions: [_session('s1', '终端 1', 'ws1')],
        child: Scaffold(
          key: key,
          drawer: const CortermSidebar(),
          body: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    key.currentState!.openDrawer();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('会话'));
    await tester.pumpAndSettle();
    expect(find.text('新建会话'), findsOneWidget);
  });

  testWidgets('搜索：未输入显示最近会话，输入后按分组过滤（design/03）', (tester) async {
    await tester.pumpWidget(
      _harness(
        workspaces: [_ws('ws1', 'CortexTerminal2', 'w1')],
        workers: [_worker('w1', 'Mac mini')],
        sessions: [_session('s1', '终端 1', 'ws1')],
        child: const SearchScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('最近会话'), findsOneWidget);
    expect(find.text('终端 1'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Cortex');
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('工作区'), findsOneWidget);
    expect(find.text('CortexTerminal2'), findsOneWidget);
    expect(find.text('最近会话'), findsNothing);
  });

  testWidgets('工作区详情：名称/电脑/路径 + 会话列表（design/01 §5-§6）', (tester) async {
    await tester.pumpWidget(
      _harness(
        workspaces: [_ws('ws1', 'CortexTerminal2', 'w1')],
        workers: [_worker('w1', 'Mac mini')],
        sessions: [
          _session('s1', '终端 1', 'ws1'),
          _session('s2', '终端 2', 'ws1', running: false),
        ],
        child: const WorkspaceDetailScreen(workspaceId: 'ws1'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('CortexTerminal2'), findsOneWidget);
    expect(find.textContaining('Mac mini'), findsWidgets);
    expect(find.text('终端 1'), findsOneWidget);
    expect(find.textContaining('进行中'), findsOneWidget);
    expect(find.text('终端 2'), findsOneWidget);
    expect(find.textContaining('已结束'), findsOneWidget);
    // 不展示 Agent 类型。
    expect(find.text('Claude Code'), findsNothing);
    expect(find.text('Shell'), findsNothing);
  });
}
