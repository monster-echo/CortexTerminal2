import 'package:flutter_test/flutter_test.dart';

import 'package:corterm_mobile/features/settings/about_screen.dart';
import 'package:corterm_mobile/features/settings/preferences_screen.dart';
import 'package:corterm_mobile/features/settings/security_screen.dart';
import 'package:corterm_mobile/features/settings/settings_screen.dart';
import 'package:corterm_mobile/features/settings/terminal_theme_editor_screen.dart';
import 'package:corterm_mobile/features/settings/terminal_themes_screen.dart';

import 'test_harness.dart';

void main() {
  setUp(() async {
    await initPageTestFixtures();
  });

  testWidgets('PreferencesScreen 构建并显示设置项', (tester) async {
    await settlePage(tester, const PreferencesScreen());

    expect(find.text('设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SettingsScreen 构建成功（别名页）', (tester) async {
    await settlePage(tester, const SettingsScreen());

    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('SecurityScreen 构建并显示安全设置', (tester) async {
    await settlePage(tester, const SecurityScreen());

    expect(find.text('安全'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AboutScreen 构建并显示版本', (tester) async {
    await settlePage(tester, const AboutScreen());

    expect(find.text('关于'), findsOneWidget);
    expect(find.textContaining('1.0.0'), findsWidgets);
  });

  testWidgets('TerminalThemesScreen 构建并列出主题', (tester) async {
    await settlePage(tester, const TerminalThemesScreen());

    expect(find.byType(TerminalThemesScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TerminalThemeEditorScreen 构建成功', (tester) async {
    await settlePage(tester, const TerminalThemeEditorScreen());

    expect(find.byType(TerminalThemeEditorScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
