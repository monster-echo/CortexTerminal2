import 'package:corterm_mobile/core/api/api_client.dart';
import 'package:corterm_mobile/features/session/presentation/session_recovery_panel.dart';
import 'package:corterm_mobile/features/session/session_diagnostics.dart';
import 'package:corterm_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnusedApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Diagnostics extends SessionDiagnostics {
  _Diagnostics(this.report) : super(_UnusedApi());
  SessionDiagnostic report;
  bool fail = false;
  int calls = 0;
  @override
  Future<SessionDiagnostic> check(String id) async {
    calls++;
    if (fail) throw StateError('offline');
    return report;
  }
}

Future<void> _showPanel(WidgetTester tester, _Diagnostics diagnostics) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sessionDiagnosticsProvider.overrideWithValue(diagnostics)],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: SessionRecoveryPanel(sessionId: 's1'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'denied remote Mac shows directory and instructions; recovery can be checked again',
    (tester) async {
      final diagnostics = _Diagnostics(
        const SessionDiagnostic(
          state: 'waiting-for-output',
          hasOutput: false,
          directoryAccess: 'permission-denied',
          platform: 'macos',
          directory: '/workspace/project',
        ),
      );
      await _showPanel(tester, diagnostics);
      final t = AppLocalizations.of(
        tester.element(find.byType(SessionRecoveryPanel)),
      )!;
      expect(find.text(t.terminalDirectoryDenied), findsOneWidget);
      expect(find.text(t.terminalRemoteMacSteps), findsOneWidget);
      expect(find.text('/workspace/project'), findsOneWidget);
      diagnostics.report = const SessionDiagnostic(
        state: 'ready',
        hasOutput: true,
        directoryAccess: 'not-checked',
        platform: 'macos',
      );
      await tester.tap(find.text(t.terminalRecheck));
      await tester.pumpAndSettle();
      expect(find.text(t.terminalDiagnosticReady), findsOneWidget);
      expect(find.text(t.terminalRemoteMacSteps), findsNothing);
      expect(diagnostics.calls, 2);
    },
  );

  testWidgets(
    'timeout does not claim permission denied; failed diagnosis still offers help',
    (tester) async {
      final diagnostics = _Diagnostics(
        const SessionDiagnostic(
          state: 'waiting-for-output',
          hasOutput: false,
          directoryAccess: 'timed-out',
          platform: 'macos',
        ),
      );
      await _showPanel(tester, diagnostics);
      final t = AppLocalizations.of(
        tester.element(find.byType(SessionRecoveryPanel)),
      )!;
      expect(find.text(t.terminalDirectoryTimeout), findsOneWidget);
      expect(find.text(t.terminalDirectoryDenied), findsNothing);
      diagnostics.fail = true;
      await tester.tap(find.text(t.terminalRecheck));
      await tester.pumpAndSettle();
      expect(find.text(t.terminalDiagnosticUnavailable), findsOneWidget);
      expect(find.text(t.terminalPermissionGuide), findsOneWidget);
    },
  );
}
