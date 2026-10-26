import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corterm_mobile/core/models/workspace.dart';
import 'package:corterm_mobile/features/search/search_screen.dart';
import 'package:corterm_mobile/features/sessions/data/sessions_providers.dart';
import 'package:corterm_mobile/features/workspaces/data/workspace_providers.dart';

import 'pages/test_harness.dart';

void main() {
  setUp(initPageTestFixtures);
  testWidgets('loading does not report no results', (tester) async {
    final pending = Completer<List<Workspace>>();
    await tester.pumpWidget(
      await pageHarness(
        const SearchScreen(),
        extra: [
          workspacesProvider.overrideWith((ref) => pending.future),
          sessionsProvider.overrideWith((ref) async => []),
          workersProvider.overrideWith((ref) async => []),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('无结果'), findsNothing);
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('无结果'), findsOneWidget);
  });
  testWidgets('partial failure retains results and retries failed source', (
    tester,
  ) async {
    var sessionRequests = 0;
    var workspaceRequests = 0;
    await tester.pumpWidget(
      await pageHarness(
        const SearchScreen(),
        extra: [
          workspacesProvider.overrideWith((ref) async {
            workspaceRequests++;
            return const [
              Workspace(workspaceId: 'ws1', workerId: 'w1', name: 'project'),
            ];
          }),
          sessionsProvider.overrideWith((ref) async {
            sessionRequests++;
            if (sessionRequests == 1) throw StateError('offline');
            return [];
          }),
          workersProvider.overrideWith((ref) async => []),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'project');
    await tester.pumpAndSettle();
    expect(find.text('project'), findsNWidgets(2));
    expect(find.textContaining('会话加载失败'), findsOneWidget);
    expect(find.text('无结果'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(sessionRequests, 2);
    expect(workspaceRequests, 1);
    expect(find.textContaining('加载失败'), findsNothing);
  });
}
