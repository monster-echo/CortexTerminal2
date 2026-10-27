import 'package:flutter_test/flutter_test.dart';

import 'package:corterm_mobile/features/files/presentation/file_preview_screen.dart';
import 'package:corterm_mobile/features/files/presentation/files_screen.dart';

import 'test_harness.dart';

void main() {
  setUp(() async {
    await initPageTestFixtures();
  });

  testWidgets('FilesScreen 构建并列出 fake 目录', (tester) async {
    await settlePage(
      tester,
      const FilesScreen(
        workspaceId: 'ws1',
        workspaceName: '主工作区',
        rootPath: '/root',
      ),
    );

    expect(find.text('README.md'), findsOneWidget);
    expect(find.byType(FilesScreen), findsOneWidget);
  });

  testWidgets('FilePreviewScreen 构建并加载文本内容', (tester) async {
    await settlePage(
      tester,
      const FilePreviewScreen(
        workspaceId: 'ws1',
        path: 'README.md',
        name: 'README.md',
        sizeBytes: 1234,
      ),
    );

    expect(find.byType(FilePreviewScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
