import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/analytics/analytics_service.dart';
import '../core/auth/auth_controller.dart';
import '../core/storage/app_preferences.dart';
import '../features/activate/activate_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/phone_login_screen.dart';
import '../features/workers/presentation/worker_select_screen.dart';
import '../features/computers/presentation/computer_detail_screen.dart';
import '../features/computers/presentation/computers_screen.dart';
import '../features/computers/presentation/pair_computer_screen.dart';
import '../features/diagnostics/diagnostics_screen.dart';
import '../features/files/presentation/file_preview_screen.dart';
import '../features/files/presentation/files_screen.dart';
import '../features/legal/legal_screens.dart';
import '../core/legal/legal_documents.dart';
import '../features/home/home_shell.dart';
import '../features/home/adaptive_workspace_shell.dart';
import '../features/membership/presentation/me_screen.dart';
import '../features/membership/presentation/membership_screen.dart';
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
      final atLogin =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/login/phone';
      final atLegal = state.matchedLocation.startsWith('/legal/');
      if (state.uri.path == '/') {
        return status == AuthStatus.unauthenticated ? '/login' : '/home';
      }
      if (atLegal) return null;
      if (status == AuthStatus.loading) return atLogin ? '/login' : '/home';
      if (status == AuthStatus.unauthenticated) {
        return atLogin ? null : '/login';
      }
      if (atLogin) return '/home';
      return null;
    },
    routes: [
      _animatedRoute(
        path: '/login',
        builder: (_, _) => const LoginScreen(),
        routes: [
          _animatedRoute(
            path: 'phone',
            builder: (_, state) =>
                PhoneLoginScreen(initialConsent: state.extra == true),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AdaptiveWorkspaceShell(
          location: state.uri,
          navigationShell: shell,
          child: shell,
        ),
        branches: [
          StatefulShellBranch(
            observers: [ref.watch(analyticsProvider).observer],
            routes: [
              _animatedRoute(
                path: '/home',
                builder: (_, _) => const HomeShell(),
              ),
              _animatedRoute(
                path: '/workers/select',
                builder: (_, _) => const WorkerSelectScreen(),
              ),
              _animatedRoute(
                path: '/search',
                builder: (_, _) => const SearchScreen(),
              ),

              // 电脑（Worker）
              _animatedRoute(
                path: '/workspaces/new',
                builder: (_, _) => const NewWorkspaceScreen(),
              ),
              _animatedRoute(
                path: '/folder-picker',
                builder: (context, state) => FolderPickerScreen(
                  workerId: state.uri.queryParameters['workerId'] ?? '',
                ),
              ),
              _animatedRoute(
                path: '/workspaces/:workspaceId',
                builder: (context, state) => WorkspaceDetailScreen(
                  workspaceId: state.pathParameters['workspaceId']!,
                ),
              ),

              // Session
              _animatedRoute(
                path: '/sessions/new',
                builder: (context, state) => NewSessionFlowScreen(
                  lockWorkspaceId: state.uri.queryParameters['workspaceId'],
                ),
              ),
              _animatedRoute(
                path: '/sessions/ungrouped',
                builder: (_, _) => const UngroupedSessionsScreen(),
              ),
              _animatedRoute(
                path: '/sessions/:sessionId',
                builder: (context, state) => SessionTerminalScreen(
                  sessionId: state.pathParameters['sessionId']!,
                ),
              ),

              // 文件 / 端口转发（Dark Tool Context，归属 Workspace）
              _animatedRoute(
                path: '/workspaces/:workspaceId/files',
                builder: (context, state) => FilesScreen(
                  workspaceId: state.pathParameters['workspaceId']!,
                  workspaceName: state.uri.queryParameters['name'] ?? '',
                  rootPath: state.uri.queryParameters['root'] ?? '',
                ),
              ),
              _animatedRoute(
                path: '/workspaces/:workspaceId/files/preview',
                builder: (context, state) => FilePreviewScreen(
                  workspaceId: state.pathParameters['workspaceId']!,
                  path: state.uri.queryParameters['path'] ?? '/',
                  name: state.uri.queryParameters['name'] ?? '',
                  sizeBytes:
                      int.tryParse(state.uri.queryParameters['size'] ?? '') ??
                      0,
                ),
              ),
              _animatedRoute(
                path: '/workspaces/:workspaceId/tunnels',
                builder: (context, state) => PortForwardingScreen(
                  workspaceId: state.pathParameters['workspaceId']!,
                ),
              ),

              // 账户 / 设置
            ],
          ),
          StatefulShellBranch(
            observers: [ref.watch(analyticsProvider).observer],
            routes: [
              _animatedRoute(
                path: '/computers',
                builder: (_, _) => const ComputersScreen(),
              ),
              _animatedRoute(
                path: '/activate',
                builder: (_, _) => const ActivateScreen(),
              ),
              _animatedRoute(
                path: '/computers/new',
                builder: (_, _) => const PairComputerScreen(),
              ),
              _animatedRoute(
                path: '/computers/:workerId',
                builder: (context, state) => ComputerDetailScreen(
                  workerId: state.pathParameters['workerId']!,
                ),
              ),

              // 工作区
            ],
          ),
          StatefulShellBranch(
            observers: [ref.watch(analyticsProvider).observer],
            routes: [
              _animatedRoute(path: '/me', builder: (_, _) => const MeScreen()),
              _animatedRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
              ),
              _animatedRoute(
                path: '/settings/membership',
                builder: (_, _) => const MembershipScreen(),
              ),
              _animatedRoute(
                path: '/settings/profile',
                builder: (_, _) => const ProfileScreen(),
              ),
              _animatedRoute(
                path: '/settings/support',
                builder: (_, _) => const SupportScreen(),
              ),
              _animatedRoute(
                path: '/settings/feedback',
                builder: (_, _) => const FeedbackScreen(),
              ),
              _animatedRoute(
                path: '/settings/about',
                builder: (_, _) => const AboutScreen(),
              ),
              _animatedRoute(
                path: '/diagnostics',
                builder: (_, _) => const DiagnosticsScreen(),
              ),
              _animatedRoute(
                path: '/settings/preferences',
                builder: (_, _) => const PreferencesScreen(),
              ),
              _animatedRoute(
                path: '/settings/terminal-themes',
                builder: (_, _) => const TerminalThemesScreen(),
              ),
              _animatedRoute(
                path: '/settings/terminal-themes/edit',
                builder: (context, state) => TerminalThemeEditorScreen(
                  initial: state.extra as TerminalColorScheme?,
                ),
              ),
              _animatedRoute(
                path: '/settings/security',
                builder: (_, _) => const SecurityScreen(),
              ),
              _animatedRoute(
                path: '/settings/redeem',
                builder: (_, _) => const RedeemScreen(),
              ),
              _animatedRoute(
                path: '/settings/referral',
                builder: (_, _) => const ReferralScreen(),
              ),
            ],
          ),
        ],
      ),

      // 法律文档（登录合规勾选 + Settings 双入口）。法律页无认证门槛。
      _animatedRoute(
        path: '/legal/:doc',
        builder: (context, state) {
          final doc = LegalRoute.values.byName(state.pathParameters['doc']!);
          final localeTag = ref.read(localeProvider);
          return LegalDocumentScreen(
            document: switch (doc) {
              LegalRoute.privacy => privacyPolicyOf(
                localeTag ?? Localizations.localeOf(context).languageCode,
              ),
              LegalRoute.terms => termsOfServiceOf(
                localeTag ?? Localizations.localeOf(context).languageCode,
              ),
              LegalRoute.deletion =>
                (localeTag ?? Localizations.localeOf(context).languageCode)
                        .startsWith('zh')
                    ? zhAccountDeletion
                    : enAccountDeletion,
            },
          );
        },
      ),
    ],
  );
});

/// ShadApp.router wraps WidgetsApp, so go_router otherwise chooses
/// NoTransitionPage and bypasses the application's page transition theme.
GoRoute _animatedRoute({
  required String path,
  required GoRouterWidgetBuilder builder,
  List<RouteBase> routes = const [],
}) => GoRoute(
  path: path,
  routes: routes,
  pageBuilder: (context, state) => MaterialPage<void>(
    key: state.pageKey,
    name: state.name ?? state.matchedLocation,
    arguments: state.extra,
    restorationId: state.pageKey.value,
    child: builder(context, state),
  ),
);
