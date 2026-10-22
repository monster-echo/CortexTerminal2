import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:worker_ui/core/app_scope.dart';
import 'package:worker_ui/core/corterm_service.dart';
import 'package:worker_ui/core/models.dart';
import 'package:worker_ui/screens/dashboard_screen.dart';
import 'package:worker_ui/screens/settings_screen.dart';
import 'package:worker_ui/theme/app_theme.dart';

/// Fake service：不跑真实进程，只喂内存数据。
class _FakeService extends CortermService {
  _FakeService() : super(cortermPath: '/tmp/fake-corterm');

  @override
  Future<Status> status() async => const Status(
    version: '0.5.14',
    pid: 123,
    uptime: '1d 2h',
    gateway: 'https://corterm.rwecho.top',
    workerId: 'worker-host',
    authenticated: true,
    user: 'alice',
    authExpiry: 'expires in 1d',
    gatewayVersion: '1.2.3',
    latestWorkerVersion: '0.5.15',
    updateAvailable: true,
    workers: [
      // workerId 与顶部 workerId 一致且在线 —— hero「已连接」的前提。
      WorkerInfo(
        workerId: 'worker-host',
        name: 'box',
        operatingSystem: 'osx',
        version: '0.5.14',
        isOnline: true,
      ),
    ],
  );
}

void main() {
  Widget wrap(Widget child) => ShadApp(
    theme: shadLightTheme(),
    home: AppScope(
      service: _FakeService(),
      child: Scaffold(body: child),
    ),
  );

  testWidgets(
    'dashboard panel renders hero, computers and this-device fields',
    (tester) async {
      await tester.pumpWidget(wrap(const DashboardScreen()));
      await tester.pumpAndSettle();

      // 连接状态和账号常驻；电脑列表默认收起并可展开。
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('box'), findsNothing);
      await tester.tap(find.text('My computers'));
      await tester.pumpAndSettle();
      expect(find.text('box'), findsOneWidget);
      await tester.tap(find.text('My computers'));
      await tester.pumpAndSettle();
      expect(find.text('box'), findsNothing);
      expect(find.text('worker-host'), findsOneWidget);
      expect(find.text('0.5.14'), findsWidgets);
    },
  );

  testWidgets('dashboard remains usable at minimum window width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(const DashboardScreen()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('My computers'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Settings'), 160);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('dashboard shows error banner when service throws', (
    tester,
  ) async {
    final failing = _FailingService();
    await tester.pumpWidget(
      wrap(AppScope(service: failing, child: const DashboardScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets(
    'settings shows preferences only (management entries live on the panel)',
    (tester) async {
      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pumpAndSettle();

      // 默认 locale 是 en，设置页只剩偏好项；管理入口已上移概览面板
      for (final label in ['Theme', 'Language', 'Launch at login']) {
        expect(find.text(label), findsOneWidget, reason: '缺少偏好项 $label');
      }
      for (final label in ['Auth', 'Agent Tools', 'Diagnostics']) {
        expect(find.text(label), findsNothing, reason: '管理入口 $label 不应留在设置页');
      }
    },
  );
}

class _FailingService extends CortermService {
  _FailingService() : super(cortermPath: '/tmp/fake-corterm');

  @override
  Future<Status> status() async => throw CortermException('boom');
}
