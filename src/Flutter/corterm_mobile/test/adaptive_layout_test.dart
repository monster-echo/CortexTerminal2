import 'package:corterm_mobile/app/theme/corterm_theme.dart';
import 'package:corterm_mobile/features/home/adaptive_workspace_shell.dart';
import 'package:corterm_mobile/features/sessions/data/sessions_providers.dart';
import 'package:corterm_mobile/features/workspaces/data/workspace_providers.dart';
import 'package:corterm_mobile/l10n/app_localizations.dart';
import 'package:corterm_mobile/shared/layout/adaptive_page_scaffold.dart';
import 'package:corterm_mobile/shared/layout/adaptive_sheet.dart';
import 'package:corterm_mobile/shared/layout/adaptive_window.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:corterm_mobile/core/storage/app_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _open = WindowLayout(
  size: Size(951, 669),
  safeArea: EdgeInsets.only(right: 84),
  regularWidth: true,
  controlEdge: ControlEdge.right,
  statusBottom: 100,
);
const _closed = WindowLayout(
  size: Size(466, 678),
  safeArea: EdgeInsets.only(right: 84),
  controlEdge: ControlEdge.right,
  statusBottom: 100,
);

late SharedPreferences _prefs;
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });
  testWidgets('a long action sheet scrolls in a short window', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(466, 360);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAdaptiveModalBottomSheet<void>(
                context: context,
                builder: (_) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 12; i++)
                      ListTile(title: Text('Action $i')),
                  ],
                ),
              ),
              child: const Text('Menu'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(find.text('Action 11').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'folding and rotating preserve the same page and its edit state',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final geometry = ValueNotifier(_open);
      addTearDown(geometry.dispose);
      final probeKey = GlobalKey<_EditingPageState>();
      final router = GoRouter(
        routes: [
          ShellRoute(
            builder: (_, state, child) =>
                AdaptiveWorkspaceShell(location: state.uri, child: child),
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => _EditingPage(key: probeKey),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      tester.view.physicalSize = _open.size;
      await tester.pumpWidget(_harness(router, geometry));
      await tester.pumpAndSettle();
      final state = probeKey.currentState;
      await tester.enterText(
        find.byKey(const ValueKey('edit')),
        'keep my command',
      );
      expect(
        find.byKey(const PageStorageKey('expanded-workspace-navigation')),
        findsOneWidget,
      );

      final expandedWidth = tester.getSize(find.byType(_EditingPage)).width;
      await tester.tap(find.byTooltip('Hide workspace sidebar'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Show workspace sidebar'), findsOneWidget);
      expect(_prefs.getBool('ui.directory_collapsed'), isTrue);
      expect(
        tester.getSize(find.byType(_EditingPage)).width,
        greaterThan(expandedWidth),
      );
      expect(probeKey.currentState, same(state));
      expect(find.text('keep my command'), findsOneWidget);

      for (final layout in [
        _closed,
        const WindowLayout(size: Size(669, 951), regularWidth: true),
        const WindowLayout(size: Size(420, 669)),
        _open,
      ]) {
        tester.view.physicalSize = layout.size;
        geometry.value = layout;
        await tester.pumpAndSettle();
        expect(probeKey.currentState, same(state));
        expect(find.text('keep my command'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      expect(find.byTooltip('Show workspace sidebar'), findsOneWidget);
      await tester.tap(find.byTooltip('Show workspace sidebar'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Hide workspace sidebar'), findsOneWidget);
      expect(probeKey.currentState, same(state));
      expect(find.text('keep my command'), findsOneWidget);
    },
  );

  testWidgets(
    'an active fold separates the two panes without covering content',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = _open.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final geometry = ValueNotifier(
        const WindowLayout(
          size: Size(951, 669),
          safeArea: EdgeInsets.only(right: 84),
          regularWidth: true,
          controlEdge: ControlEdge.right,
          statusBottom: 100,
          regions: [
            WindowRegion(
              frame: Rect.fromLTWH(440, 0, 70, 669),
              isDivision: true,
            ),
          ],
        ),
      );
      addTearDown(geometry.dispose);
      final router = GoRouter(
        routes: [
          ShellRoute(
            builder: (_, state, child) =>
                AdaptiveWorkspaceShell(location: state.uri, child: child),
            routes: [
              GoRoute(path: '/', builder: (_, _) => const _EditingPage()),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_harness(router, geometry));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(_EditingPage)).dx, 510);
      await tester.tap(find.byTooltip('Hide workspace sidebar'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(_EditingPage)).dx, 510);
      expect(find.byTooltip('Show workspace sidebar'), findsOneWidget);

      expect(
        tester.getTopRight(find.byKey(const ValueKey('edit'))).dx,
        lessThanOrEqualTo(867),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _harness(GoRouter router, ValueNotifier<WindowLayout> geometry) =>
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(_prefs),
        workspacesProvider.overrideWith((ref) async => []),
        workersProvider.overrideWith((ref) async => []),
        sessionsProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(extensions: const [CortermColors.light]),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ValueListenableBuilder<WindowLayout>(
          valueListenable: geometry,
          builder: (context, layout, _) => WindowLayoutScope(
            layout: layout,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: layout.safeArea,
                viewPadding: layout.safeArea,
              ),
              child: child!,
            ),
          ),
        ),
      ),
    );

class _EditingPage extends StatefulWidget {
  const _EditingPage({super.key});

  @override
  State<_EditingPage> createState() => _EditingPageState();
}

class _EditingPageState extends State<_EditingPage> {
  @override
  Widget build(BuildContext context) => AdaptivePageScaffold(
    appBar: AppBar(
      title: const Text('Session'),
      actions: [
        IconButton(
          key: const ValueKey('action'),
          tooltip: 'Files',
          onPressed: () {},
          icon: const Icon(Icons.folder_outlined),
        ),
      ],
    ),
    body: ListView(
      children: const [
        TextField(key: ValueKey('edit')),
        SizedBox(height: 800),
      ],
    ),
  );
}
