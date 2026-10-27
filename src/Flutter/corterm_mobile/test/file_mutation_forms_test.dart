import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corterm_mobile/features/files/data/file_repository.dart';
import 'package:corterm_mobile/features/files/presentation/files_screen.dart';

import 'fakes.dart';
import 'pages/test_harness.dart';

class _Files extends FakeFileRepo {
  int trashed = 0;
  int restored = 0;
  @override
  Future<void> trash({
    required String workspaceId,
    required String path,
    required String trashId,
  }) async {
    trashed++;
  }

  @override
  Future<void> restoreTrash({
    required String workspaceId,
    required String trashId,
  }) async {
    restored++;
    if (restored == 1) throw StateError('conflict');
  }

  int renames = 0;
  int writes = 0;
  String? renamedTo;
  @override
  Future<void> rename({
    required String workspaceId,
    required String path,
    required String newName,
  }) async {
    renames++;
    renamedTo = newName;
    if (renames == 1) throw StateError('rename unavailable');
  }

  @override
  Future<void> writeText({
    required String workspaceId,
    required String path,
    required String content,
  }) async {
    writes++;
  }
}

void main() {
  setUp(initPageTestFixtures);
  const page = FilesScreen(
    workspaceId: 'ws1',
    workspaceName: 'Test',
    rootPath: '/root',
  );
  testWidgets(
    'trash receipt survives sheet close and restore failure permits retry',
    (tester) async {
      final files = _Files();
      await tester.pumpWidget(
        await pageHarness(
          page,
          extra: [fileRepositoryProvider.overrideWithValue(files)],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_horiz).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('移到回收站'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移到回收站').last);
      await tester.pumpAndSettle();
      expect(files.trashed, 1);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('最近删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();
      expect(files.restored, 1);
      expect(find.textContaining('暂时无法完成文件操作'), findsOneWidget);
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();
      expect(files.restored, 2);
      expect(find.text('暂无删除记录'), findsOneWidget);
    },
  );
  testWidgets('rename error keeps edited filename and can retry', (
    tester,
  ) async {
    final files = _Files();
    await tester.pumpWidget(
      await pageHarness(
        page,
        extra: [fileRepositoryProvider.overrideWithValue(files)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'renamed.md');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(files.renames, 1);
    expect(find.text('renamed.md'), findsOneWidget);
    expect(find.textContaining('暂时无法完成文件操作'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '保存'));
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(files.renames, 2);
    expect(files.renamedTo, 'renamed.md');
  });
  testWidgets(
    'new text file cannot overwrite existing content without explicit choice',
    (tester) async {
      final files = _Files();
      await tester.pumpWidget(
        await pageHarness(
          page,
          extra: [fileRepositoryProvider.overrideWithValue(files)],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('新建'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建文本文件'));
      await tester.pumpAndSettle();
      // First field belongs to the dimmed page's folder filter.
      await tester.enterText(find.byType(TextField).at(1), 'README.md');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
            .onPressed,
        isNull,
      );
      expect(files.writes, 0);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, '保存'));
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(files.writes, 1);
    },
  );
}
