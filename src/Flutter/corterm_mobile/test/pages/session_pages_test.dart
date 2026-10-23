import 'package:flutter_test/flutter_test.dart';

import 'package:corterm_mobile/features/session/presentation/session_terminal_screen.dart';

import 'test_harness.dart';

void main() {
  setUp(() async {
    await initPageTestFixtures();
  });

  testWidgets('SessionTerminalScreen 构建并附着 fake 会话', (tester) async {
    // 终端光标闪烁有循环动画，不能用 pumpAndSettle。
    await settlePage(
        tester, const SessionTerminalScreen(sessionId: 'sess-0001'));

    expect(find.byType(SessionTerminalScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
