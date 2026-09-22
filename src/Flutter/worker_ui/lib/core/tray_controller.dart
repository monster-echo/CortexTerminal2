import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';

import '../l10n/app_strings.dart';
import 'binary_locator.dart';
import 'corterm_service.dart';
import 'models.dart';
import 'self_updater.dart';
import 'settings.dart';

/// 托盘菜单动作（需要 UI 配合的动作由 App 监听处理）。
enum TrayCommand { none, show, login, logout, about, quit }

/// 全局导航 key：托盘菜单「登录」需要 push 认证页。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 托盘菜单控制器：动态显示登录状态 / 登录登出 / worker 数量，每 30s 刷新。
class TrayController extends ChangeNotifier {
  TrayController._();

  static final TrayController instance = TrayController._();

  /// 托盘菜单动作（App 监听后执行，执行完置回 none）。
  static final ValueNotifier<TrayCommand> command = ValueNotifier(TrayCommand.none);

  CortermService? service;
  Status? status;
  bool _launchAtStartup = false;
  Timer? _timer;

  Future<void> init() async {
    // Windows 托盘只认 .ico（png 会显示空白图标）；macOS 用 template png。
    final icon = Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png';
    await trayManager.setIcon(icon, isTemplate: !Platform.isWindows);
    trayManager.addListener(_TrayListener());
    await refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final paths = await resolveBinaryPaths();
      if (paths == null) return;
      service ??= CortermService(cortermPath: paths.corterm, cortapPath: paths.cortap);
      status = await service!.status();
    } catch (_) {
      status = null;
    }
    await _loadLaunchAtStartup();
    await _buildMenu();
    notifyListeners();
  }

  Future<void> _loadLaunchAtStartup() async {
    try {
      _launchAtStartup = await launchAtStartup.isEnabled();
    } catch (_) {
      _launchAtStartup = false;
    }
  }

  Future<void> _toggleLaunchAtStartup() async {
    try {
      if (_launchAtStartup) {
        await launchAtStartup.disable();
      } else {
        await launchAtStartup.enable();
      }
      _launchAtStartup = !_launchAtStartup;
    } catch (_) {
      // 切换失败保持原状态（macOS 下需 app 在 /Applications）
    }
    await _buildMenu();
  }

  Future<void> _buildMenu() async {
    String t(String key) => AppStrings.of(Settings.instance.locale, key);
    final s = status;
    final loggedIn = s?.authenticated ?? false;
    final user = s?.user;
    final workers = s?.workers ?? const <WorkerInfo>[];
    final online = workers.where((w) => w.isOnline).length;

    final items = <MenuItem>[
      // 登录状态（禁用行）：已登录直接显示用户名
      MenuItem(
        key: 'auth',
        label: loggedIn ? (user ?? t('tray.loggedIn')) : t('tray.notLoggedIn'),
        disabled: true,
      ),
      // worker 数量（禁用行）
      MenuItem(
        key: 'workers',
        label: t('tray.workers').replaceAll('{online}', '$online').replaceAll('{total}', '${workers.length}'),
        disabled: true,
      ),
      // 开机启动（复选框）
      MenuItem.checkbox(
        key: 'startup',
        label: t('tray.launchAtStartup'),
        checked: _launchAtStartup,
        onClick: (_) => _toggleLaunchAtStartup(),
      ),
      // 未登录才给登录入口；已登录给登出
      if (loggedIn)
        MenuItem(key: 'logout', label: t('tray.logout'), onClick: (_) => command.value = TrayCommand.logout)
      else
        MenuItem(key: 'login', label: t('tray.login'), onClick: (_) => command.value = TrayCommand.login),
      // 关于（版本 / 版权 / worker 版本）
      MenuItem(key: 'about', label: t('tray.about'), onClick: (_) => command.value = TrayCommand.about),
      // 退出
      MenuItem(
        key: 'quit',
        label: t('tray.quit'),
        onClick: (_) => command.value = TrayCommand.quit,
      ),
    ];

    await trayManager.setContextMenu(Menu(items: items));
    final statusText = loggedIn ? (user ?? '') : t('tray.notLoggedIn');
    await trayManager.setToolTip('${t('appTitle')} v$appVersion · $statusText · $online/${workers.length}');
  }

  /// 托盘登出：直接跑 corterm logout --json，然后刷新菜单。
  Future<void> logoutFromTray() async {
    try {
      await service?.logout();
    } catch (_) {
      // 登出失败也要刷新，让菜单反映真实状态
    }
    await refresh();
  }
}

/// 左键单击 → 显示主窗口；右键 → 弹出上下文菜单（tray_manager 不会自动弹，必须 popUpContextMenu）。
class _TrayListener extends TrayListener {
  @override
  void onTrayIconMouseDown() {
    TrayController.command.value = TrayCommand.show;
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }
}
