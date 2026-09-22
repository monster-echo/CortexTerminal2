import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/analytics/analytics_service.dart';
import '../core/auth/auth_controller.dart';
import '../core/storage/app_preferences.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/diagnostics/diagnostics_screen.dart';
import '../features/files/presentation/files_screen.dart';
import '../features/files/presentation/file_preview_screen.dart';
import '../features/workers/presentation/workers_screen.dart';
import '../features/workers/presentation/worker_upgrade_screen.dart';
import '../features/legal/legal_screens.dart';
import '../features/membership/presentation/redeem_screen.dart';
import '../features/membership/presentation/referral_screen.dart';
import '../features/home/home_screen.dart';
import '../features/activate/activate_screen.dart';
import '../features/membership/presentation/me_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/sessions/presentation/all_sessions_screen.dart';
import '../features/support/presentation/support_screen.dart';
import '../features/feedback/presentation/feedback_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/about_screen.dart';
import '../features/settings/preferences_screen.dart';
import '../features/settings/terminal_theme_editor_screen.dart';
import '../features/settings/terminal_themes_screen.dart';
import '../core/models/terminal_color_scheme.dart';
import '../features/settings/security_screen.dart';
import '../features/workspace/workspace_screen.dart';

/// 路由（§49）：/login /home /workspace /sessions /settings。
/// 不为单个 session 建 route —— Terminal 内切换由 Workspace State 控制。
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => notifier.value++);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: notifier,
    observers: [ref.watch(analyticsProvider).observer],
    // 未知路径兜底：渲染占位页而不是抛 GoException 蓝屏。
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.compass, size: 40),
            const SizedBox(height: 12),
            Text(state.error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ShadButton.outline(
              onPressed: () => context.go('/home'),
              child: const Text('Go home'),
            ),
          ],
        ),
      ),
    ),
    redirect: (context, state) {
      final status = ref.read(authProvider).status;
      final atLogin = state.matchedLocation == '/login';
      final atLegal = state.matchedLocation.startsWith('/legal/');
      // 根路径没有对应路由（initialLocation 是 /home）：显式归位，
      // 否则未认证判定走完后 fall-through 到匹配阶段会抛
      // GoException(no routes for location: /)，整页变异常蓝屏。
      if (state.uri.path == '/') {
        return status == AuthStatus.unauthenticated ? '/login' : '/home';
      }
      if (atLegal) return null; // 法律文档无认证门槛（登录合规勾选入口）。
      if (status == AuthStatus.loading) return atLogin ? '/login' : '/home';
      if (status == AuthStatus.unauthenticated) return atLogin ? null : '/login';
      if (atLogin) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      // Terminal 页面固定深色（§2）：终端本体深色，外壳跟随浅色会露白底。
      GoRoute(
        path: '/workspace',
        builder: (_, _) => const WorkspaceScreen(),
      ),
      GoRoute(path: '/sessions', builder: (_, _) => const AllSessionsScreen()),
      GoRoute(path: '/me', builder: (_, _) => const MeScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/settings/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/settings/support', builder: (_, _) => const SupportScreen()),
      GoRoute(path: '/settings/feedback', builder: (_, _) => const FeedbackScreen()),
      GoRoute(path: '/settings/about', builder: (_, _) => const AboutScreen()),
      GoRoute(path: '/settings/preferences', builder: (_, _) => const PreferencesScreen()),
      GoRoute(
        path: '/settings/terminal-themes',
        builder: (_, _) => const TerminalThemesScreen(),
      ),
      GoRoute(
        path: '/settings/terminal-themes/edit',
        builder: (context, state) =>
            TerminalThemeEditorScreen(initial: state.extra as TerminalColorScheme?),
      ),
      GoRoute(path: '/settings/security', builder: (_, _) => const SecurityScreen()),
GoRoute(path: '/settings/redeem', builder: (_, _) => const RedeemScreen()),
GoRoute(path: '/settings/referral', builder: (_, _) => const ReferralScreen()),
      GoRoute(path: '/activate', builder: (_, _) => const ActivateScreen()),
      GoRoute(path: '/workers', builder: (_, _) => const WorkersScreen()),
      GoRoute(path: '/diagnostics', builder: (_, _) => const DiagnosticsScreen()),
      GoRoute(
        path: '/workers/:workerId/upgrade',
        builder: (context, state) => WorkerUpgradeScreen(
          workerId: state.pathParameters['workerId']!,
          name: state.uri.queryParameters['name'] ?? '',
        ),
      ),
      GoRoute(
        path: '/files/:sessionId',
        builder: (context, state) => FilesScreen(
          sessionId: state.pathParameters['sessionId']!,
        ),
      ),
      GoRoute(
        path: '/files/:sessionId/preview',
        builder: (context, state) => FilePreviewScreen(
          workspaceId: state.uri.queryParameters['workspaceId'] ?? '',
          path: state.uri.queryParameters['path'] ?? '/',
          name: state.uri.queryParameters['name'] ?? '',
          sizeBytes: int.tryParse(state.uri.queryParameters['size'] ?? '') ?? 0,
        ),
      ),
      // 法律文档（登录合规勾选 + Settings 双入口）。法律页无认证门槛。
      GoRoute(
        path: '/legal/:doc',
        builder: (context, state) {
          final doc = LegalRoute.values.byName(state.pathParameters['doc']!);
          final localeTag = ref.read(localeProvider);
          return LegalDocumentScreen(
            document: switch (doc) {
              LegalRoute.privacy => privacyPolicyOf(localeTag),
              LegalRoute.terms => termsOfServiceOf(localeTag),
            },
          );
        },
      ),
    ],
  );
});
