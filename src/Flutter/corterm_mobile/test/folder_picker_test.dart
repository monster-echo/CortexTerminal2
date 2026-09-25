import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corterm_mobile/app/theme/corterm_theme.dart';
import 'package:corterm_mobile/core/models/worker.dart';
import 'package:corterm_mobile/core/models/workspace.dart';
import 'package:corterm_mobile/features/files/data/file_repository.dart';
import 'package:corterm_mobile/features/sessions/data/sessions_providers.dart';
import 'package:corterm_mobile/features/workers/presentation/worker_select_screen.dart';
import 'package:corterm_mobile/features/workspaces/data/workspace_providers.dart';
import 'package:corterm_mobile/features/workspaces/presentation/folder_picker_screen.dart';

import 'fakes.dart';

WorkerSummary _worker(String id, String name, {bool online = true}) =>
    WorkerSummary(
      workerId: id,
      name: name,
      hostname: '$id.local',
      isOnline: online,
      sessionCount: 0,
    );

/// 电脑选择页 harness：外层按钮 push 选择页，捕获 pop 返回值。
Widget _selectHarness(ProviderContainer container, ValueChanged<WorkerSummary?> onPicked) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        extensions: const [CortermColors.light],
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final result = await Navigator.push<WorkerSummary>(
                  context,
                  MaterialPageRoute(builder: (_) => const WorkerSelectScreen()),
                );
                onPicked(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('电脑选择页：列出电脑并点选返回', (tester) async {
    final container = ProviderContainer(overrides: [
      workersProvider.overrideWith((ref) async =>
          [_worker('w1', 'Mac mini'), _worker('w2', 'Linux box', online: false)]),
    ]);
    addTearDown(container.dispose);

    WorkerSummary? picked;
    await tester.pumpWidget(_selectHarness(container, (r) => picked = r));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Mac mini'), findsOneWidget);
    expect(find.text('Linux box'), findsOneWidget);
    expect(find.textContaining('离线'), findsOneWidget);

    await tester.tap(find.text('Mac mini'));
    await tester.pumpAndSettle();

    expect(picked?.workerId, 'w1');
  });

  testWidgets('电脑选择页：无电脑时显示空态', (tester) async {
    final container = ProviderContainer(overrides: [
      workersProvider.overrideWith((ref) async => const []),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(_selectHarness(container, (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('还没有配对电脑'), findsOneWidget);
  });

  group('文件夹选择器 UX（design/02 §4 + 评审修正）', () {
    late FakeFileRepo repo;

    late ProviderContainer container;
    late GoRouter router;

    Future<void> mountPicker(WidgetTester tester) async {
      container = ProviderContainer(overrides: [
        workspacesProvider.overrideWith((ref) async => [
              const Workspace(
                workspaceId: 'ws1',
                workerId: 'w1',
                name: 'Home',
                rootPath: '/Users/tester',
              ),
            ]),
        workersProvider.overrideWith((ref) async => [_worker('w1', 'Mac mini')]),
        sessionsProvider.overrideWith((ref) async => const []),
        fileRepositoryProvider.overrideWith((ref) => repo),
      ]);
      addTearDown(container.dispose);
      router = GoRouter(
        initialLocation: '/pick',
        routes: [
          GoRoute(
            path: '/pick',
            builder: (_, _) => const FolderPickerScreen(workerId: 'w1'),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            theme: ThemeData(
              useMaterial3: true,
              extensions: const [CortermColors.light],
            ),
          ),
        ),
      );
    }

    setUp(() {
      repo = FakeFileRepo();
      repo.listingBuilder = (root, path) => FileListing(
            entries: [
              if (path == 'a') ...[
                const FileEntry(
                    name: 'deep',
                    isDirectory: true,
                    sizeBytes: 0,
                    modifiedUtc: null),
              ] else ...[
                const FileEntry(
                    name: 'a',
                    isDirectory: true,
                    sizeBytes: 0,
                    modifiedUtc: null),
                const FileEntry(
                    name: 'b',
                    isDirectory: true,
                    sizeBytes: 0,
                    modifiedUtc: null),
              ],
            ],
            truncated: false,
          );
    });

    testWidgets('每次都从起点打开：不做位置记忆（回归：曾从上次目录开始）', (tester) async {
      await mountPicker(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // 进入 a/
      await tester.tap(find.text('a'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.listForWorkerCalls.last.path, 'a');

      // 模拟离开页面再次进入：卸载（go 到空页）再挂载，起点必须是根（path=''）
      repo.listForWorkerCalls.clear();
      router.go('/');
      await tester.pump(const Duration(milliseconds: 100));
      router.go('/pick');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.listForWorkerCalls.last.path, '');
    });

    testWidgets('「返回上级」在任何列表状态下可用：空目录也能退出去', (tester) async {
      // 根有 a/b；a/ 目录为空
      repo.listingBuilder = (root, path) => path == 'a'
          ? const FileListing(entries: [], truncated: false)
          : FileListing(entries: const [
              FileEntry(
                  name: 'a',
                  isDirectory: true,
                  sizeBytes: 0,
                  modifiedUtc: null),
              FileEntry(
                  name: 'b',
                  isDirectory: true,
                  sizeBytes: 0,
                  modifiedUtc: null),
            ], truncated: false);

      await mountPicker(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('a'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      // 空目录：显示空态，但仍有「..」行与返回上级按钮
      expect(find.text('没有子文件夹'), findsOneWidget);
      expect(find.text('..'), findsOneWidget);
      expect(find.byTooltip('返回上级'), findsOneWidget);

      await tester.tap(find.text('..'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.listForWorkerCalls.last.path, '');
    });

    testWidgets('错误态保留导航出口：返回上级 / 回到起点 / 重试', (tester) async {
      repo.listingBuilder = (root, path) {
        if (path == 'locked') {
          // 延迟抛错：让 FutureBuilder 先订阅（否则算未处理异步异常）
          return Future.delayed(
            const Duration(milliseconds: 10),
            () => throw StateError('access denied'),
          );
        }
        return FileListing(entries: const [
          FileEntry(
              name: 'locked',
              isDirectory: true,
              sizeBytes: 0,
              modifiedUtc: null),
        ], truncated: false);
      };

      await mountPicker(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // 进入会抛错的目录
      await tester.tap(find.text('locked'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('access denied'), findsOneWidget);
      expect(find.text('返回上级'), findsOneWidget);
      expect(find.text('回到起点'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      // 回到起点 → 恢复正常列表（根下是 locked 目录）
      await tester.tap(find.text('回到起点'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('locked'), findsOneWidget);
      expect(find.textContaining('access denied'), findsNothing);
    });

    testWidgets('「回到起点」一键返回浏览根', (tester) async {
      await mountPicker(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('a'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('deep'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.listForWorkerCalls.last.path, 'a/deep');

      await tester.tap(find.byTooltip('回到起点'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.listForWorkerCalls.last.path, '');
    });
  });
}
