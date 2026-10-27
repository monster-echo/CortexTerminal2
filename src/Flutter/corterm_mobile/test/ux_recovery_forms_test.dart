import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:corterm_mobile/core/auth/auth_repository.dart';
import 'package:corterm_mobile/core/storage/app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:corterm_mobile/features/feedback/presentation/feedback_screen.dart';
import 'package:corterm_mobile/features/settings/security_screen.dart';
import 'package:corterm_mobile/features/settings/terminal_theme_editor_screen.dart';
import 'package:corterm_mobile/features/files/data/file_repository.dart';
import 'package:corterm_mobile/features/files/data/file_transfer_control.dart';
import 'package:corterm_mobile/features/files/presentation/file_preview_screen.dart';

import 'pages/test_harness.dart';
import 'fakes.dart';

class _Auth extends Fake implements AuthRepository {
  int requests = 0;
  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    requests++;
    if (requests == 1) throw StateError('Incorrect password');
  }
}

class _Files extends FakeFileRepo {
  int downloads = 0;
  @override
  Future<Uint8List> downloadBytes({
    required String workspaceId,
    required String path,
    FileTransferControl? control,
  }) async {
    downloads++;
    return Uint8List.fromList(utf8.encode('你好，Corterm\n中文测试'));
  }
}

void main() {
  setUp(initPageTestFixtures);
  testWidgets(
    'password failure retains form and retries once with same inputs',
    (tester) async {
      final api = _Auth();
      await tester.pumpWidget(
        await pageHarness(
          const SecurityScreen(),
          extra: [authRepositoryProvider.overrideWithValue(api)],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('修改密码'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'old-password');
      await tester.enterText(fields.at(1), 'new-password');
      await tester.enterText(fields.at(2), 'new-password');
      await tester.ensureVisible(find.widgetWithText(FilledButton, '保存'));
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Incorrect password'), findsOneWidget);
      expect(
        tester.widget<TextField>(fields.at(1)).controller!.text,
        'new-password',
      );
      expect(api.requests, 1);
      await tester.ensureVisible(find.widgetWithText(FilledButton, '保存'));
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(api.requests, 2);
      expect(find.byType(TextField), findsNothing);
    },
  );
  testWidgets('mismatched password confirmation makes no request', (
    tester,
  ) async {
    final api = _Auth();
    await tester.pumpWidget(
      await pageHarness(
        const SecurityScreen(),
        extra: [authRepositoryProvider.overrideWithValue(api)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改密码'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'old');
    await tester.enterText(find.byType(TextField).at(1), 'new');
    await tester.enterText(find.byType(TextField).at(2), 'different');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '保存'));
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(api.requests, 0);
    expect(find.text('两次输入的新密码不一致。'), findsOneWidget);
  });
  testWidgets('text preview decodes UTF-8 and supports finding Chinese text', (
    tester,
  ) async {
    final files = _Files();
    await tester.pumpWidget(
      await pageHarness(
        const FilePreviewScreen(
          workspaceId: 'ws1',
          path: 'readme.md',
          name: 'readme.md',
          sizeBytes: 100,
        ),
        extra: [fileRepositoryProvider.overrideWithValue(files)],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('你好'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '中文');
    await tester.pumpAndSettle();
    expect(find.text('1 处匹配'), findsOneWidget);
    expect(files.downloads, 1);
  });
  testWidgets('unsupported preview does not pre-download a large file', (
    tester,
  ) async {
    final files = _Files();
    await tester.pumpWidget(
      await pageHarness(
        const FilePreviewScreen(
          workspaceId: 'ws1',
          path: 'archive.zip',
          name: 'archive.zip',
          sizeBytes: 100000000,
        ),
        extra: [fileRepositoryProvider.overrideWithValue(files)],
      ),
    );
    await tester.pumpAndSettle();
    expect(files.downloads, 0);
    expect(find.textContaining('不支持'), findsOneWidget);
  });
  testWidgets(
    'theme editor refuses accidental back and keeps edits on cancel',
    (tester) async {
      await tester.pumpWidget(
        await pageHarness(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => context.push('/edit'),
                child: const Text('open'),
              ),
            ),
          ),
          extraRoutes: [
            GoRoute(
              path: '/edit',
              builder: (_, _) => const TerminalThemeEditorScreen(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(ShadInput).first, 'My theme');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的修改？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('My theme'), findsOneWidget);
    },
  );
  testWidgets('feedback text draft survives leaving and reopening the page', (
    tester,
  ) async {
    await tester.pumpWidget(await pageHarness(const FeedbackScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(ShadInputFormField).first,
      '复现步骤与详细的问题描述',
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(await pageHarness(const FeedbackScreen()));
    await tester.pumpAndSettle();
    expect(find.text('复现步骤与详细的问题描述'), findsOneWidget);
  });
  test('accessory key choices persist across provider containers', () async {
    final prefs = await SharedPreferences.getInstance();
    final first = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    await first.read(terminalKeyLayoutProvider.notifier).set([
      'paste',
      'esc',
      'ctrl',
    ]);
    first.dispose();
    final second = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    expect(second.read(terminalKeyLayoutProvider), ['paste', 'esc', 'ctrl']);
    second.dispose();
  });
  test(
    'cancellation terminates pending negotiation instead of waiting for it',
    () async {
      final control = FileTransferControl();
      final pending = control.guard(Completer<void>().future);
      final cancelled = expectLater(
        pending,
        throwsA(
          isA<DioException>().having(
            (error) => error.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      control.cancel();
      await cancelled;
      control.dispose();
    },
  );
}
