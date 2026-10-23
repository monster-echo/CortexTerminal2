import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_strings.dart';
import '../screens/about_screen.dart';
import '../screens/agent_tools_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/doctor_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/update_screen.dart';
import '../widgets/app_bar.dart';

/// 全局 navigator key：托盘侧需要 context 时使用（toast）。
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// 子页统一包一层 Scaffold + 返回栏。
Widget _page(BuildContext context, String title, Widget body) => Scaffold(
      appBar: WorkerAppBar(title: title),
      body: body,
    );

/// 声明式路由表：/ 为概览面板（Tailscale 式主页），其余为推送子页。
final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, _) => const DashboardScreen()),
    GoRoute(
      path: '/auth',
      builder: (context, _) =>
          _page(context, AppStrings.t(context, 'auth.title'), const AuthScreen()),
    ),
    GoRoute(
      path: '/agent-tools',
      builder: (context, _) => _page(
        context,
        AppStrings.t(context, 'agentTools.title'),
        const AgentToolsScreen(),
      ),
    ),
    GoRoute(
      path: '/doctor',
      // 诊断页自带 AppBar（重新运行按钮在导航栏 actions 里）。
      builder: (context, state) => DoctorScreen(directory: state.uri.queryParameters['directory']),
    ),
    GoRoute(
      path: '/update',
      // 更新页自带 AppBar（重新检查按钮在导航栏 actions 里）。
      builder: (context, _) => const UpdateScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, _) =>
          _page(context, AppStrings.t(context, 'settings.title'), const SettingsScreen()),
    ),
    GoRoute(
      path: '/about',
      builder: (context, _) =>
          _page(context, AppStrings.t(context, 'about.title'), const AboutScreen()),
    ),
  ],
);
