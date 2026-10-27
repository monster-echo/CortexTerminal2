import 'package:flutter_test/flutter_test.dart';

import 'package:corterm_mobile/features/workers/presentation/worker_select_screen.dart';
import 'package:corterm_mobile/features/workspaces/presentation/folder_picker_screen.dart';
import 'package:corterm_mobile/features/workspaces/presentation/new_session_flow_screen.dart';
import 'package:corterm_mobile/features/workspaces/presentation/new_workspace_screen.dart';
import 'package:corterm_mobile/features/workspaces/presentation/ungrouped_sessions_screen.dart';
import 'package:corterm_mobile/features/workspaces/presentation/workspace_detail_screen.dart';

import 'test_harness.dart';

void main() {
  setUp(() async {
    await initPageTestFixtures();
  });

  testWidgets('WorkerSelectScreen 构建并列出电脑', (tester) async {
    await settlePage(tester, const WorkerSelectScreen());

    expect(find.text('Mac mini'), findsOneWidget);
    expect(find.text('Linux box'), findsOneWidget);
  });

  testWidgets('FolderPickerScreen 构建并列出目录', (tester) async {
    await settlePage(tester, const FolderPickerScreen(workerId: 'w1'));

    expect(find.byType(FolderPickerScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NewSessionFlowScreen 构建成功', (tester) async {
    await settlePage(tester, const NewSessionFlowScreen());

    expect(find.byType(NewSessionFlowScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NewWorkspaceScreen 构建并列出电脑', (tester) async {
    await settlePage(tester, const NewWorkspaceScreen());

    expect(find.byType(NewWorkspaceScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('UngroupedSessionsScreen 构建成功', (tester) async {
    await settlePage(tester, const UngroupedSessionsScreen());

    expect(find.byType(UngroupedSessionsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WorkspaceDetailScreen 构建并显示工作区会话', (tester) async {
    await settlePage(tester, const WorkspaceDetailScreen(workspaceId: 'ws1'));

    expect(find.byType(WorkspaceDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
