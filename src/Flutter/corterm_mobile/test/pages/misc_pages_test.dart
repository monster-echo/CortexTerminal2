import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corterm_mobile/features/activate/activate_screen.dart';
import 'package:corterm_mobile/features/diagnostics/diagnostics_screen.dart';
import 'package:corterm_mobile/features/search/search_screen.dart';
import 'package:corterm_mobile/features/tunnels/presentation/port_forwarding_screen.dart';

import 'test_harness.dart';

void main() {
  setUp(() async {
    await initPageTestFixtures();
  });

  testWidgets('SearchScreen 构建且可输入搜索词', (tester) async {
    await settlePage(tester, const SearchScreen());

    await tester.enterText(find.byType(TextField).first, '构建');
    await tester.pump();
    expect(find.text('构建'), findsOneWidget);
  });

  testWidgets('PortForwardingScreen 构建成功（无隧道）', (tester) async {
    await settlePage(tester, const PortForwardingScreen(workspaceId: 'ws1'));

    expect(find.byType(PortForwardingScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DiagnosticsScreen 构建成功（探测指向不可达地址快速失败）', (tester) async {
    await settlePage(tester, const DiagnosticsScreen());

    expect(find.byType(DiagnosticsScreen), findsOneWidget);
  });

  testWidgets('ActivateScreen 构建成功', (tester) async {
    await settlePage(tester, const ActivateScreen());

    expect(find.byType(ActivateScreen), findsOneWidget);
  });
}
