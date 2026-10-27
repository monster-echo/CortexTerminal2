import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:corterm_mobile/features/auth/presentation/login_screen.dart';
import 'package:corterm_mobile/features/computers/presentation/computer_detail_screen.dart';
import 'package:corterm_mobile/features/computers/presentation/computers_screen.dart';
import 'package:corterm_mobile/features/computers/presentation/pair_computer_screen.dart';

import 'test_harness.dart';

void main() {
  setUp(() async {
    await initPageTestFixtures();
  });

  testWidgets('LoginScreen 构建并展示登录表单', (tester) async {
    await settlePage(tester, const LoginScreen());

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
  });

  testWidgets('ComputersScreen 构建并列出 fake 电脑', (tester) async {
    await settlePage(tester, const ComputersScreen());

    expect(find.text('电脑'), findsOneWidget);
    expect(find.text('Mac mini'), findsOneWidget);
    expect(find.text('Linux box'), findsOneWidget);
  });

  testWidgets('ComputerDetailScreen 构建并显示 worker 信息', (tester) async {
    await settlePage(tester, const ComputerDetailScreen(workerId: 'w1'));

    expect(find.text('Mac mini'), findsWidgets);
  });

  testWidgets('PairComputerScreen 构建成功', (tester) async {
    await settlePage(tester, const PairComputerScreen());

    expect(find.byType(PairComputerScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
