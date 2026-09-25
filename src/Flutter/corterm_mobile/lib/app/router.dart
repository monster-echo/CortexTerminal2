import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/analytics/analytics_service.dart';
import '../core/auth/auth_controller.dart';
import '../core/storage/app_preferences.dart';
import '../features/activate/activate_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/workers/presentation/worker_select_screen.dart';
import '../features/computers/presentation/computer_detail_screen.dart';
import '../features/computers/presentation/pair_computer_screen.dart';
import '../features/files/presentation/file_preview_screen.dart';
import '../features/files/presentation/files_screen.dart';
import '../features/legal/legal_screens.dart';
import '../features/home/home_shell.dart';
import '../features/membership/presentation/me_screen.dart';
import '../features/membership/presentation/redeem_screen.dart';
import '../features/membership/presentation/referral_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/search/search_screen.dart';
import '../features/session/presentation/session_terminal_screen.dart';
import '../features/settings/about_screen.dart';
import '../features/settings/preferences_screen.dart';
import '../features/settings/security_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/terminal_theme_editor_screen.dart';
import '../features/settings/terminal_themes_screen.dart';
import '../features/support/presentation/support_screen.dart';
import '../features/feedback/presentation/feedback_screen.dart';
import '../features/tunnels/presentation/port_forwarding_screen.dart';
import '../features/workspaces/presentation/folder_picker_screen.dart';
import '../features/workspaces/presentation/new_session_flow_screen.dart';
import '../features/workspaces/presentation/ungrouped_sessions_screen.dart';
import '../features/workspaces/presentation/new_workspace_screen.dart';
import '../features/workspaces/presentation/workspace_detail_screen.dart';
import '../core/models/terminal_color_scheme.dart';

/// 路由（design/00 §2 页面信息架构）。
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => notifier.value++);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: notifier,
    observers: [ref.watch(analyticsProvider).observer],
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
      if (state.uri.path == '/') {
        return status == AuthStatus.unauthenticated ? '/login' : '/home';
      }
      if (atLegal) return null;
      if (status == AuthStatus.loading) return atLogin ? '/login' : '/home';
      if (status == AuthStatus.unauthenticated) return atLogin ? null : '/login';
      if (atLogin) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/activate', builder: (_, _) => const ActivateScreen()),
      GoRoute(path: '/workers/select', builder: (_, _) => const WorkerSelectScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeShell()),
      GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),

      // 电脑（Worker）
      GoRoute(
          path: '/computers/new', builder: (_, _) => const PairComputerScreen()),
      GoRoute(
        path: '/computers/:workerId',
        builder: (context, state) => ComputerDetailScreen(
          workerId: state.pathParameters['workerId']!,
        ),
      ),

      // 工作区
      GoRoute(
          path: '/workspaces/new',
          builder: (_, _) => const NewWorkspaceScreen()),
      GoRoute(
        path: '/folder-picker',
        builder: (context, state) => FolderPickerScreen(
          workerId: state.uri.queryParameters['workerId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/workspaces/:workspaceId',
        builder: (context, state) => WorkspaceDetailScreen(
          workspaceId: state.pathParameters['workspaceId']!,
        ),
      ),

      // Session
      GoRoute(
        path: '/sessions/new',
        builder: (context, state) => NewSessionFlowScreen(
          lockWorkspaceId: state.uri.queryParameters['workspaceId'],
        ),
      ),
      GoRoute(
          path: '/sessions/ungrouped',
          builder: (_, _) => const UngroupedSessionsScreen()),
      GoRoute(
        path: '/sessions/:sessionId',
        builder: (context, state) => SessionTerminalScreen(
          sessionId: state.pathParameters['sessionId']!,
        ),
      ),

      // 文件 / 端口转发（Dark Tool Context，归属 Workspace）
      GoRoute(
        path: '/workspaces/:workspaceId/files',
        builder: (context, state) => FilesScreen(
          workspaceId: state.pathParameters['workspaceId']!,
          workspaceName: state.uri.queryParameters['name'] ?? '',
          rootPath: state.uri.queryParameters['root'] ?? '',
        ),
      ),
      GoRoute(
        path: '/workspaces/:workspaceId/files/preview',
        builder: (context, state) => FilePreviewScreen(
          workspaceId: state.pathParameters['workspaceId']!,
          path: state.uri.queryParameters['path'] ?? '/',
          name: state.uri.queryParameters['name'] ?? '',
          sizeBytes: int.tryParse(state.uri.queryParameters['size'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/workspaces/:workspaceId/tunnels',
        builder: (context, state) => PortForwardingScreen(
          workspaceId: state.pathParameters['workspaceId']!,
        ),
      ),

      // 账户 / 设置
      GoRoute(path: '/me', builder: (_, _) => const MeScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/settings/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/settings/support', builder: (_, _) => const SupportScreen()),
      GoRoute(path: '/settings/feedback', builder: (_, _) => const FeedbackScreen()),
      GoRoute(path: '/settings/about', builder: (_, _) => const AboutScreen()),
      GoRoute(
          path: '/settings/preferences',
          builder: (_, _) => const PreferencesScreen()),
      GoRoute(
        path: '/settings/terminal-themes',
        builder: (_, _) => const TerminalThemesScreen(),
      ),
      GoRoute(
        path: '/settings/terminal-themes/edit',
        builder: (context, state) =>
            TerminalThemeEditorScreen(initial: state.extra as TerminalColorScheme?),
      ),
      GoRoute(
          path: '/settings/security',
          builder: (_, _) => const SecurityScreen()),
      GoRoute(path: '/settings/redeem', builder: (_, _) => const RedeemScreen()),
      GoRoute(
          path: '/settings/referral',
          builder: (_, _) => const ReferralScreen()),

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
