import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:corterm_mobile/core/models/session.dart';
import 'package:corterm_mobile/core/models/worker.dart';
import 'package:corterm_mobile/core/models/workspace.dart';
import 'package:corterm_mobile/features/sessions/data/session_repository.dart';
import 'package:corterm_mobile/features/sessions/data/sessions_providers.dart';
import 'package:corterm_mobile/features/workspaces/data/workspace_providers.dart';
import 'package:corterm_mobile/features/workspaces/presentation/new_session_flow_screen.dart';
import 'package:corterm_mobile/features/workspaces/presentation/workspace_detail_screen.dart';

import 'pages/test_harness.dart';

class _CreateRepo extends Fake implements SessionRepository {
  int calls = 0;
  String? worker;
  String? workspace;
  String? name;
  Completer<SessionSummary>? pending;
  bool fail = false;
  SessionSummary get result => SessionSummary(
    sessionId: 'created-session',
    name: '默认名称',
    workerId: 'w1',
    status: SessionStatus.attached,
    createdAt: DateTime(2026),
    lastActivityAt: DateTime(2026),
    workspaceId: workspace ?? '',
  );
  @override
  Future<SessionSummary> create({
    required int columns,
    required int rows,
    String? workerId,
    String? workspaceId,
    String? cwd,
    String? name,
  }) async {
    calls++;
    worker = workerId;
    workspace = workspaceId;
    this.name = name;
    if (fail) throw StateError('创建失败');
    return pending == null ? result : pending!.future;
  }
}

void main() {
  setUp(initPageTestFixtures);
  Future<void> mount(
    WidgetTester tester,
    Widget page,
    _CreateRepo repo, {
    List<Override> extra = const [],
  }) async {
    await tester.pumpWidget(
      await pageHarness(
        page,
        extra: [sessionRepositoryProvider.overrideWithValue(repo), ...extra],
        extraRoutes: [
          GoRoute(
            path: '/computers/new',
            builder: (_, _) => const Scaffold(body: Text('pair computer')),
          ),
          GoRoute(
            path: '/workspaces/new',
            builder: (_, _) => const Scaffold(body: Text('new workspace')),
          ),
          GoRoute(
            path: '/computers/:id',
            builder: (_, _) => const Scaffold(body: Text('computer detail')),
          ),
          GoRoute(
            path: '/sessions/:id',
            builder: (_, state) =>
                Scaffold(body: Text('terminal:${state.pathParameters['id']}')),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('缺少电脑提供配对入口且不创建会话', (tester) async {
    final repo = _CreateRepo();
    await mount(
      tester,
      const NewSessionFlowScreen(),
      repo,
      extra: [workersProvider.overrideWith((ref) async => [])],
    );
    await tester.pumpAndSettle();
    expect(repo.calls, 0);
    await tester.tap(find.text('连接电脑'));
    await tester.pumpAndSettle();
    expect(find.text('pair computer'), findsOneWidget);
  });

  testWidgets('缺少工作区提供创建入口', (tester) async {
    final repo = _CreateRepo();
    await mount(
      tester,
      const NewSessionFlowScreen(),
      repo,
      extra: [workspacesProvider.overrideWith((ref) async => [])],
    );
    await tester.pumpAndSettle();
    expect(repo.calls, 0);
    await tester.tap(find.text('新建工作区'));
    await tester.pumpAndSettle();
    expect(find.text('new workspace'), findsOneWidget);
  });

  testWidgets('离线目标提供电脑详情入口', (tester) async {
    final repo = _CreateRepo();
    await mount(
      tester,
      const NewSessionFlowScreen(lockWorkspaceId: 'ws1'),
      repo,
      extra: [
        workersProvider.overrideWith(
          (ref) async => const [
            WorkerSummary(
              workerId: 'w1',
              name: 'Mac',
              isOnline: false,
              sessionCount: 0,
            ),
          ],
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(repo.calls, 0);
    await tester.tap(find.text('查看电脑'));
    await tester.pumpAndSettle();
    expect(find.text('computer detail'), findsOneWidget);
  });

  testWidgets('已失效的指定工作区不会静默创建到其他目录', (tester) async {
    final repo = _CreateRepo();
    await mount(
      tester,
      const NewSessionFlowScreen(lockWorkspaceId: 'deleted'),
      repo,
    );
    await tester.pumpAndSettle();
    expect(repo.calls, 0);
    expect(find.text('选择工作区'), findsOneWidget);
    expect(find.textContaining('这个工作区已不可用'), findsOneWidget);
  });

  testWidgets('工作区直接创建默认名称会话并进入终端', (tester) async {
    final repo = _CreateRepo();
    await mount(tester, const WorkspaceDetailScreen(workspaceId: 'ws1'), repo);
    await tester.tap(
      find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    await tester.pumpAndSettle();
    expect(repo.calls, 1);
    expect(repo.workspace, 'ws1');
    expect(repo.worker, 'w1');
    expect(repo.name, isNull);
    expect(find.text('terminal:created-session'), findsOneWidget);
    expect(find.byType(NewSessionFlowScreen), findsNothing);
  });

  testWidgets('已有工作区入口自动创建且等待期间不重复提交', (tester) async {
    final repo = _CreateRepo()..pending = Completer<SessionSummary>();
    await mount(
      tester,
      const NewSessionFlowScreen(lockWorkspaceId: 'ws1'),
      repo,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(repo.calls, 1);
    expect(repo.name, isNull);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('创建会话'), findsNothing);
    repo.pending!.complete(repo.result);
    await tester.pumpAndSettle();
    expect(repo.calls, 1);
    expect(find.text('terminal:created-session'), findsOneWidget);
  });

  testWidgets('直接使用第一台电脑的第一个工作区创建', (tester) async {
    final repo = _CreateRepo();
    await mount(tester, const NewSessionFlowScreen(), repo);
    await tester.pumpAndSettle();
    expect(repo.calls, 1);
    expect(repo.workspace, 'ws1');
    expect(repo.name, isNull);
    expect(find.text('terminal:created-session'), findsOneWidget);
  });

  testWidgets('多个工作区也直接使用第一个目录', (tester) async {
    final repo = _CreateRepo();
    await mount(
      tester,
      const NewSessionFlowScreen(),
      repo,
      extra: [
        workspacesProvider.overrideWith(
          (ref) async => const [
            Workspace(
              workspaceId: 'ws1',
              workerId: 'w1',
              name: '目录一',
              isDefault: true,
            ),
            Workspace(workspaceId: 'ws2', workerId: 'w1', name: '目录二'),
          ],
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(repo.calls, 1);
    expect(repo.workspace, 'ws1');
    expect(repo.name, isNull);
    expect(find.text('terminal:created-session'), findsOneWidget);
  });

  testWidgets('创建失败保留错误，用户重试后进入终端', (tester) async {
    final repo = _CreateRepo()..fail = true;
    await mount(
      tester,
      const NewSessionFlowScreen(lockWorkspaceId: 'ws1'),
      repo,
    );
    await tester.pumpAndSettle();
    expect(repo.calls, 1);
    expect(find.textContaining('创建失败'), findsOneWidget);
    repo.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(repo.calls, 2);
    expect(find.text('terminal:created-session'), findsOneWidget);
  });

  testWidgets('离线电脑的工作区不能创建会话', (tester) async {
    final repo = _CreateRepo();
    await mount(
      tester,
      const WorkspaceDetailScreen(workspaceId: 'ws1'),
      repo,
      extra: [
        workersProvider.overrideWith(
          (ref) async => const [
            WorkerSummary(
              workerId: 'w1',
              name: 'Mac mini',
              isOnline: false,
              sessionCount: 0,
            ),
          ],
        ),
      ],
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byWidgetPredicate((widget) => widget is FilledButton),
          )
          .onPressed,
      isNull,
    );
    expect(repo.calls, 0);
  });
}
