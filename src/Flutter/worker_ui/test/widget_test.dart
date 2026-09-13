import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:worker_ui/core/corterm_service.dart';
import 'package:worker_ui/core/models.dart';
import 'package:worker_ui/screens/dashboard_screen.dart';
import 'package:worker_ui/screens/settings_screen.dart';
import 'package:worker_ui/theme/app_theme.dart';

/// Fake service：不跑真实进程，只喂内存数据。
class _FakeService extends CortermService {
  _FakeService()
      : super(cortermPath: '/tmp/fake-corterm', cortapPath: '/tmp/fake-cortap');

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
          WorkerInfo(
            workerId: 'w1',
            name: 'box',
            operatingSystem: 'osx',
            version: '0.5.14',
            isOnline: true,
          ),
        ],
      );
}

void main() {
  Widget wrap(Widget child) => ShadApp(theme: shadLightTheme(), home: Scaffold(body: child));

  testWidgets('dashboard renders status fields', (tester) async {
    await tester.pumpWidget(
      wrap(DashboardScreen(service: _FakeService())),
    );
    await tester.pumpAndSettle();

    // 认证状态、用户、worker 列表都渲染出来
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('box'), findsOneWidget);
    expect(find.text('worker-host'), findsOneWidget);
    expect(find.text('0.5.14'), findsWidgets);
  });

  testWidgets('dashboard shows error banner when service throws', (tester) async {
    final failing = _FailingService();
    await tester.pumpWidget(wrap(DashboardScreen(service: failing)));
    await tester.pumpAndSettle();

    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('settings shows management section (auth/agentTools/update/doctor/sessions)', (tester) async {
    await tester.pumpWidget(
      wrap(SettingsScreen(service: _FakeService())),
    );
    await tester.pumpAndSettle();

    // 默认 locale 是 en，管理区 tile 显示英文（服务已并入启动自动拉起，不在管理区）
    for (final label in ['Auth', 'Agent Tools', 'Update', 'Doctor', 'Sessions']) {
      expect(find.text(label), findsOneWidget, reason: '缺少管理区入口 $label');
    }
  });
}

class _FailingService extends CortermService {
  _FailingService()
      : super(cortermPath: '/tmp/fake-corterm', cortapPath: '/tmp/fake-cortap');

  @override
  Future<Status> status() async => throw CortermException('boom');
}
