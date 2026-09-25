import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';


import 'package:corterm_mobile/app/theme/corterm_theme.dart';
import 'package:corterm_mobile/core/models/workspace.dart';
import 'package:corterm_mobile/features/files/data/file_repository.dart';
import 'package:corterm_mobile/features/sessions/data/sessions_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corterm_mobile/core/storage/app_preferences.dart';
import 'package:corterm_mobile/features/workspaces/data/workspace_providers.dart';

import 'package:corterm_mobile/features/workspaces/presentation/folder_picker_screen.dart';
import 'package:corterm_mobile/features/workspaces/presentation/new_workspace_screen.dart';

import 'fakes.dart';

late final AppPreferences appPrefs;

Widget _harness({
  required List<Workspace> workspaces,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      appPreferencesProvider.overrideWith((ref) => appPrefs),
      workspacesProvider.overrideWith((ref) async => workspaces),
      workersProvider.overrideWith((ref) async => const []),
      sessionsProvider.overrideWith((ref) async => const []),
      fileRepositoryProvider.overrideWith((ref) => FakeFileRepo()),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => child),
        ],
      ),
      theme: ThemeData(
        useMaterial3: true,
        extensions: const [CortermColors.light],
      ),
    ),
  );
}

/// 回归：NewWorkspaceScreen 曾在 initState 里读 GoRouterState（继承组件）
/// 导致打开页面即崩。此测试保证页面可无参直接构建。
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    appPrefs = AppPreferences(await SharedPreferences.getInstance());
  });

  testWidgets('新建工作区页可直接打开，不依赖 query', (tester) async {
    await tester.pumpWidget(_harness(
      workspaces: const [],
      child: const NewWorkspaceScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('创建工作区'), findsOneWidget);
  });

  testWidgets('文件夹选择：该电脑无工作区时回退 "~" 起点仍可浏览（design/02 §4）', (tester) async {
    await tester.pumpWidget(_harness(
      workspaces: const [],
      child: const FolderPickerScreen(workerId: 'w-new'),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    // FakeFileRepo.listForWorker 返回 Projects 目录——说明请求成功发出，
    // 而不是卡在「无法定位浏览起点」。
    expect(find.text('Projects'), findsOneWidget);
    expect(find.textContaining('无法定位浏览起点'), findsNothing);
    expect(find.text('使用当前文件夹'), findsOneWidget);
  });
}
