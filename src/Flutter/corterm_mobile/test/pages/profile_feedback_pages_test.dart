import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:corterm_mobile/features/feedback/presentation/feedback_screen.dart';
import 'package:corterm_mobile/features/profile/presentation/profile_screen.dart';
import 'package:corterm_mobile/features/support/presentation/support_screen.dart';

import 'test_harness.dart';

void main() {
  setUp(() async {
    await initPageTestFixtures();
  });

  testWidgets('ProfileScreen 构建并显示资料', (tester) async {
    await settlePage(tester, const ProfileScreen());

    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('tester'), findsWidgets);
  });

  testWidgets('SupportScreen 构建并显示客服入口', (tester) async {
    await settlePage(tester, const SupportScreen());

    expect(find.text('联系客服'), findsOneWidget);
    expect(find.text('Telegram 群组暂不可用，请稍后重试。'), findsOneWidget);
    expect(find.text('意见反馈'), findsOneWidget);
  });

  testWidgets('FeedbackScreen 构建且可输入反馈', (tester) async {
    await settlePage(tester, const FeedbackScreen());

    expect(find.byType(ShadInputFormField), findsWidgets);
    await tester.enterText(find.byType(ShadInputFormField).first, '体验不错');
    await tester.pump();
    expect(find.text('体验不错'), findsOneWidget);
  });
}
