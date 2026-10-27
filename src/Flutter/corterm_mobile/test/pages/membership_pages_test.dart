import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:corterm_mobile/features/membership/presentation/me_screen.dart';
import 'package:corterm_mobile/features/membership/presentation/membership_screen.dart';
import 'package:corterm_mobile/features/membership/presentation/redeem_screen.dart';
import 'package:corterm_mobile/features/membership/presentation/referral_screen.dart';

import 'test_harness.dart';

void main() {
  setUp(() async {
    await initPageTestFixtures();
  });

  testWidgets('MeScreen 构建并显示用户名', (tester) async {
    await settlePage(tester, const MeScreen());

    expect(find.text('tester'), findsOneWidget);
  });

  testWidgets('MembershipScreen 构建并显示套餐', (tester) async {
    await settlePage(tester, const MembershipScreen());

    expect(find.byType(MembershipScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RedeemScreen 构建且可输入兑换码', (tester) async {
    await settlePage(tester, const RedeemScreen());

    expect(find.byType(ShadInput), findsOneWidget);
    await tester.enterText(find.byType(ShadInput), 'CODE-1234');
    await tester.pump();
    expect(find.text('CODE-1234'), findsOneWidget);
  });

  testWidgets('ReferralScreen 构建并显示邀请码', (tester) async {
    await settlePage(tester, const ReferralScreen());

    expect(find.text('INVITE-1'), findsOneWidget);
  });
}
