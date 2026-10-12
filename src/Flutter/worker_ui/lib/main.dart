import 'dart:io';

import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_router.dart';
import 'core/binary_locator.dart';
import 'core/settings.dart';
import 'core/tray_controller.dart';
import 'l10n/app_strings.dart';
import 'widgets/states.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Settings.instance.load();

  // App 与 worker 一体：没有 worker 就装内置的，避免「请安装 worker」。
  await ensureWorkerInstalled();
  // 启动 UI 即确保 worker 服务在跑（best-effort，不阻塞启动）。
  await _ensureWorkerService();

  _initLaunchAtStartup(); // 先 setup，托盘菜单里的开机启动复选框才能读/切
  await _initWindow();
  await TrayController.instance.init();
  TrayController.command.addListener(_handleTrayCommand);
  TrayController.toast.addListener(_handleTrayToast);

  runApp(const CortexApp());
}

// ── 窗口：关闭 → 隐藏到托盘 ──
Future<void> _initWindow() async {
  await windowManager.ensureInitialized();
  // Tailscale 式窄面板窗口：固定窄宽，主窗口即状态面板。
  final options = WindowOptions(
    size: const Size(380, 640),
    minimumSize: const Size(360, 520),
    center: true,
    title: AppStrings.of(Settings.instance.locale, 'appTitle'),
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  await windowManager.setPreventClose(true);
  windowManager.addListener(_AppWindowListener());
}

class _AppWindowListener extends WindowListener {
  @override
  void onWindowClose() {
    // 专业桌面程序行为：点关闭 = 收进托盘，不退出。
    windowManager.hide();
  }
}

// ── 服务：启动 UI 即确保 worker 守护进程在跑（best-effort）──
Future<void> _ensureWorkerService() async {
  try {
    final paths = await resolveBinaryPaths();
    if (paths == null) return;
    await Process.run(paths.corterm, ['start', '--json']);
  } catch (_) {
    // 服务未安装 / 已运行等场景都忽略，不阻塞 UI。
  }
}

// ── 托盘菜单动作 ──
void _handleTrayCommand() {
  switch (TrayController.command.value) {
    case TrayCommand.show:
      _showWindow();
    case TrayCommand.login:
      _showWindow();
      _openAuthScreen();
    case TrayCommand.about:
      _showWindow();
      _openAboutScreen();
    case TrayCommand.quit:
      exit(0);
    case TrayCommand.logout:
    case TrayCommand.none:
      break;
  }
  TrayController.command.value = TrayCommand.none;
}

/// 托盘侧的提示（如开机启动开关结果）：窗口可见时弹 toast，
/// 窗口隐藏时托盘菜单勾选态 / tooltip 已反映状态，不强行弹窗。
void _handleTrayToast() {
  final message = TrayController.toast.value;
  if (message == null) return;
  TrayController.toast.value = null;
  _showTrayToast(message);
}

Future<void> _showTrayToast(String message) async {
  final context = rootNavigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  if (!await windowManager.isVisible()) return;
  if (!context.mounted) return;
  showAppToast(context, message);
}

Future<void> _showWindow() async {
  await windowManager.show();
  await windowManager.focus();
}

/// 托盘「登录」→ 显示窗口并跳到认证页。
void _openAuthScreen() {
  _showWindow();
  appRouter.push('/auth');
}

/// 托盘「关于」→ 显示窗口并跳到关于页。
void _openAboutScreen() {
  _showWindow();
  appRouter.push('/about');
}

// ── 开机启动（macOS SMAppService / Windows 注册表 / Linux autostart）──
void _initLaunchAtStartup() {
  if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) return;
  launchAtStartup.setup(
    appName: AppStrings.of(Settings.instance.locale, 'appTitle'),
    appPath: Platform.resolvedExecutable,
  );
}
