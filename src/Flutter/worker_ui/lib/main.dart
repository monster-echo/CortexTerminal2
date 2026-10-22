import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_router.dart';
import 'core/binary_locator.dart';
import 'core/settings.dart';
import 'core/tray_controller.dart';
import 'core/worker_process_controller.dart';
import 'l10n/app_strings.dart';
import 'widgets/states.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Settings.instance.load();

  // App 与 worker 一体：没有 worker 就装内置的，避免「请安装 worker」。
  await _ensureWorkerProcess();

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
  // 紧凑桌面工具窗口；窄窗口仍可滚动浏览。
  final options = WindowOptions(
    size: const Size(560, 720),
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
// 所有桌面平台均由 App 托管，不调用独立 CLI 的系统服务。
Future<void> _ensureWorkerProcess() async {
  final repaired = await ensureWorkerInstalled(syncBundledWorker: true);
  await WorkerProcessController.instance.start(forceRestartRunning: repaired);
}

/// 托盘退出：先停托管的 worker，再退出进程。
/// stop() 只接这里 —— 绝不能挂到全局 exit 钩子：SelfUpdater 更新 UI 时也会
/// exit(0)，worker 必须存活，更新后由 OS/安装器把应用拉回来。
Future<void> _quit() async {
  try {
    await WorkerProcessController.instance.stop();
  } catch (_) {
    // 停不下来也要退出，不阻塞退出路径。
  }
  exit(0);
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
      unawaited(_quit());
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
