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
import 'package:corterm_mobile/features/workspaces/presentation/new_session_flow_screen.dart';
import 'package:corterm_mobile/features/workspaces/presentation/workspace_detail_screen.dart';

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

SessionSummary _session(String id, String name, String workspaceId,
        {bool running = true}) =>
    SessionSummary(
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

Widget _harness({
  required List<Workspace> workspaces,
  required List<WorkerSummary> workers,
  required List<SessionSummary> sessions,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      workspacesProvider.overrideWith((ref) async => workspaces),
      workersProvider.overrideWith((ref) async => workers),
      sessionsProvider.overrideWith((ref) async => sessions),
      workspaceSessionsProvider.overrideWith((ref, workspaceId) =>
          sessions.where((s) => s.workspaceId == workspaceId).toList()),
      sessionRepositoryProvider.overrideWith((ref) => _FakeSessionRepo()),
    ],
    child: MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        extensions: const [CortermColors.light],
      ),
      home: child,
    ),
  );
}

void main() {
  testWidgets('首页：工作区 Tab 展示工作区名与所属电脑（design/01 §2）', (tester) async {
    await tester.pumpWidget(_harness(
      workspaces: [_ws('ws1', 'CortexTerminal2', 'w1')],
      workers: [_worker('w1', 'Mac mini')],
      sessions: [_session('s1', '终端 1', 'ws1')],
      child: const HomeShell(),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('CortexTerminal2'), findsOneWidget);
    expect(find.text('Mac mini · 1 个会话运行中'), findsOneWidget);
  });

  testWidgets('首页：切到电脑 Tab 展示在线状态与工作区数（design/01 §3）', (tester) async {
    await tester.pumpWidget(_harness(
      workspaces: [_ws('ws1', 'CortexTerminal2', 'w1')],
      workers: [_worker('w1', 'Mac mini')],
      sessions: const [],
      child: const HomeShell(),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('电脑'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Mac mini'), findsOneWidget);
    expect(find.text('在线 · 1 个工作区'), findsOneWidget);
  });

  testWidgets('侧边栏：首个工作区默认展开显示会话，底部有新建与头像（design/01 §4）', (tester) async {
    final key = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(_harness(
      workspaces: [_ws('ws1', 'CortexTerminal2', 'w1')],
      workers: [_worker('w1', 'Mac mini')],
      sessions: [_session('s1', '终端 1', 'ws1')],
      child: Scaffold(
        key: key,
        drawer: const CortermSidebar(),
        body: const SizedBox.shrink(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    key.currentState!.openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('Corterm'), findsOneWidget);
    // 首个工作区默认展开 → 其会话可见。
    expect(find.text('终端 1'), findsOneWidget);
    expect(find.text('新建'), findsOneWidget);
  });

  testWidgets('搜索：未输入显示最近会话，输入后按分组过滤（design/03）', (tester) async {
    await tester.pumpWidget(_harness(
      workspaces: [_ws('ws1', 'CortexTerminal2', 'w1')],
      workers: [_worker('w1', 'Mac mini')],
      sessions: [_session('s1', '终端 1', 'ws1')],
      child: const SearchScreen(),
    ));
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
    await tester.pumpWidget(_harness(
      workspaces: [_ws('ws1', 'CortexTerminal2', 'w1')],
      workers: [_worker('w1', 'Mac mini')],
      sessions: [
        _session('s1', '终端 1', 'ws1'),
        _session('s2', '终端 2', 'ws1', running: false),
      ],
      child: const WorkspaceDetailScreen(workspaceId: 'ws1'),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('CortexTerminal2'), findsOneWidget);
    expect(find.text('电脑：Mac mini'), findsOneWidget);
    expect(find.text('终端 1'), findsOneWidget);
    expect(find.textContaining('运行中'), findsOneWidget);
    expect(find.text('终端 2'), findsOneWidget);
    expect(find.textContaining('已结束'), findsOneWidget);
    // 不展示 Agent 类型。
    expect(find.text('Claude Code'), findsNothing);
    expect(find.text('Shell'), findsNothing);
  });

  testWidgets('新建会话：锁定工作区时只读展示并可直接创建（design/02 §5）', (tester) async {
    await tester.pumpWidget(_harness(
      workspaces: [_ws('ws1', 'CortexTerminal2', 'w1')],
      workers: [_worker('w1', 'Mac mini')],
      sessions: const [],
      child: const NewSessionFlowScreen(lockWorkspaceId: 'ws1'),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('CortexTerminal2'), findsOneWidget);
    expect(find.text('创建会话'), findsOneWidget);
    // 锁定模式：电脑以只读行展示。
  });
}
