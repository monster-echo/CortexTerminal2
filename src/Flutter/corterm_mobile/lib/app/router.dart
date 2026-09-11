import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/analytics/analytics_service.dart';
import '../core/auth/auth_controller.dart';
import '../core/storage/app_preferences.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/diagnostics/diagnostics_screen.dart';
import '../features/files/presentation/files_screen.dart';
import '../features/workers/presentation/workers_screen.dart';
import '../features/legal/legal_screens.dart';
import '../features/home/home_screen.dart';
import '../features/activate/activate_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/sessions/presentation/all_sessions_screen.dart';
import '../features/support/presentation/support_screen.dart';
import '../features/feedback/presentation/feedback_screen.dart';
import '../features/settings/settings_screen.dart';
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
    redirect: (context, state) {
      final status = ref.read(authProvider).status;
      final atLogin = state.matchedLocation == '/login';
      final atLegal = state.matchedLocation.startsWith('/legal/');
      if (atLegal) return null; // 法律文档无认证门槛（登录合规勾选入口）。
      if (status == AuthStatus.loading) return atLogin ? '/login' : '/home';
      if (status == AuthStatus.unauthenticated) return atLogin ? null : '/login';
      if (atLogin) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/workspace', builder: (_, _) => const WorkspaceScreen()),
      GoRoute(path: '/sessions', builder: (_, _) => const AllSessionsScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/settings/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/settings/support', builder: (_, _) => const SupportScreen()),
      GoRoute(path: '/settings/feedback', builder: (_, _) => const FeedbackScreen()),
      GoRoute(path: '/activate', builder: (_, _) => const ActivateScreen()),
      GoRoute(path: '/workers', builder: (_, _) => const WorkersScreen()),
      GoRoute(path: '/diagnostics', builder: (_, _) => const DiagnosticsScreen()),
      GoRoute(
        path: '/files/:sessionId',
        builder: (context, state) => FilesScreen(
          sessionId: state.pathParameters['sessionId']!,
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
