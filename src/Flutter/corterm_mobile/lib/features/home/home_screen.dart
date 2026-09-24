import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/session.dart';
import '../../core/models/worker.dart';
import '../../core/storage/app_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/install_prompt.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/sheets_and_dialogs.dart';
import '../sessions/data/session_repository.dart';
import '../sessions/data/sessions_providers.dart';
import '../session/widgets/new_session_sheet.dart';
import '../session/widgets/session_status.dart';
import '../session/session_controller.dart';

/// 首页（结构对齐 ArkTS SessionHomePage，组件只用 shadcn 标准件）：
/// 单一会话列表（活跃+历史按最近活动排序）+ 四态互斥 + 卡片左滑操作。
/// 无 shadcn 对应物的两处自绘（有据可查）：骨架占位条（包无 Skeleton）、
/// 左滑操作（包无 swipe，用 flutter_slidable）。
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _announcementShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowAnnouncement());
  }

  /// 网关公告：取第一条未关闭的弹窗（每条每设备只弹一次，对齐 ArkTS）。
  Future<void> _maybeShowAnnouncement() async {
    if (_announcementShown) return;
    _announcementShown = true;
    try {
      final repo = ref.read(sessionRepositoryProvider);
      final prefs = ref.read(appPreferencesProvider);
      final dismissed = prefs.dismissedAnnouncementIds;
      final pending = (await repo.announcements())
          .where((a) => a.id.isNotEmpty && !dismissed.contains(a.id))
          .firstOrNull;
      if (pending == null || !mounted) return;
      await _showAnnouncement(pending);
    } catch (_) {
      // 公告拉取失败不打断首页（登录/会话不依赖它），静默跳过本轮。
    }
  }

  Future<void> _showAnnouncement(GatewayAnnouncement a) async {
    final l10n = AppLocalizations.of(context)!;
    void dismiss() =>
        ref.read(appPreferencesProvider).dismissAnnouncement(a.id);
    await showCortermSheetDialog<void>(
      context: context,
      title: a.title,
      child: Builder(
        builder: (bodyContext) => Text(
          a.body,
          style: ShadTheme.of(bodyContext)
              .textTheme
              .muted
              .copyWith(color: ShadTheme.of(bodyContext).colorScheme.mutedForeground),
        ),
      ),
      actions: [
        ShadButton.ghost(
          onPressed: () {
            dismiss();
            Navigator.of(context).pop();
          },
          child: Text(l10n.cancel),
        ),
        if (a.url.isNotEmpty)
          ShadButton(
            onPressed: () async {
              dismiss();
              Navigator.of(context).pop();
              final ok = await launchUrl(Uri.parse(a.url),
                  mode: LaunchMode.externalApplication);
              if (!ok && mounted) {
                showAppToast(context, l10n.loginFailed, destructive: true);
              }
            },
            child: Text(
              a.buttonLabel.isNotEmpty ? a.buttonLabel : l10n.tunnelOpen,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final sessions = ref.watch(sessionsProvider);

    Widget body;
    if (sessions.isLoading && sessions.value == null) {
      // 骨架屏：3 张占位卡（包无 Skeleton 组件，最小自绘）。
      body = ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ShadCard(
                leading: _SkeletonBar(width: 12, height: 12, radius: 6),
                title: _SkeletonBar(width: 140, height: 14),
                description: _SkeletonBar(width: 100, height: 10),
              ),
            ),
        ],
      );
    } else if (sessions.hasError && sessions.value == null) {
      body = ErrorState(
        message: '${sessions.error}',
        onRetry: () => ref.invalidate(sessionsProvider),
      );
    } else {
      final all = [...(sessions.value ?? const [])]
        ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));

      if (all.isEmpty) {
        // 空态三分支（对齐 ArkTS）：无 Worker → 安装引导；全离线/有在线 → 文案。
        body = ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            ref.watch(workersProvider).when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: ShadProgress(value: null)),
                    ),
                  ),
                  error: (e, _) => ErrorState(message: '$e', onRetry: () {
                    ref.invalidate(workersProvider);
                  }),
                  data: (list) {
                    if (list.isEmpty) {
                      return InstallPromptCard(
                        title: l10n.installWorkerTitle,
                        intro: l10n.installWorkerIntro,
                      );
                    }
                    final anyOnline = list.any((WorkerSummary w) => w.isOnline);
                    return Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Text(
                        anyOnline ? l10n.noActiveSessions : l10n.noWorkers,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.muted
                            .copyWith(color: scheme.mutedForeground),
                      ),
                    );
                  },
                ),
          ],
        );
      } else {
        body = RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(sessionsProvider);
            await ref.read(sessionsProvider.future);
          },
          child: SlidableAutoCloseBehavior(
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: all.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _SessionCard(session: all[index]),
            ),
          ),
        );
      }
    }

    return AppShellScaffold(
      tab: ShellTab.home,
      title: l10n.homeTitle,
      actions: [
        // 新建会话：仅图标（移动端标题栏惯例），长按 tooltip 提供语义。
        Tooltip(
          message: l10n.newSession,
          child: ShadIconButton.ghost(
            foregroundColor: scheme.foreground,
            icon: const Icon(LucideIcons.plus),
            onPressed: () => showNewSessionSheet(
              context,
              onCreated: (sessionId) {
                ref.read(sessionControllerProvider.notifier).open(sessionId);
                context.go('/workspace');
              },
            ),
          ),
        ),
      ],
      body: body,
    );
  }
}

/// 会话状态徽章文案。
String sessionStatusLabel(BuildContext context, SessionStatus status) {
  final l10n = AppLocalizations.of(context)!;
  return switch (status) {
    SessionStatus.attached || SessionStatus.detachedGracePeriod => l10n.connLive,
    SessionStatus.recovering => l10n.connReconnecting,
    SessionStatus.exited || SessionStatus.expired => l10n.connExited,
  };
}

/// 会话卡片：标准 ShadCard + 状态 ShadBadge + 左滑操作。
class _SessionCard extends ConsumerWidget {
  const _SessionCard({required this.session});

  final SessionSummary session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final alive = session.status.isAlive;

    return Slidable(
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.36,
        children: [
          SlidableAction(
            onPressed: (_) async {
              HapticFeedback.selectionClick();
              final controller = TextEditingController(text: session.name);
              final ok = await showCortermSheetDialog<bool>(
                context: context,
                title: l10n.rename,
                child: ShadInputFormField(controller: controller, maxLength: 100),
                actions: [
                  ShadButton.ghost(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(l10n.cancel),
                  ),
                  ShadButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(l10n.ok),
                  ),
                ],
              );
              if (ok != true) return;
              final name = controller.text.trim();
              if (name.isEmpty || name == session.name) return;
              await ref
                  .read(sessionRepositoryProvider)
                  .rename(sessionId: session.sessionId, name: name);
              ref.invalidate(sessionsProvider);
            },
            backgroundColor: scheme.secondary,
            foregroundColor: scheme.primary,
            borderRadius: BorderRadius.circular(12),
            autoClose: true,
            icon: LucideIcons.pencil,
          ),
          SlidableAction(
            onPressed: (_) async {
              HapticFeedback.selectionClick();
              final confirmed = await showConfirmDialog(
                context: context,
                title: alive
                    ? l10n.terminateConfirmTitle(session.displayName)
                    : l10n.deleteSessionConfirmTitle(session.displayName),
                body: alive
                    ? l10n.terminateConfirmBody
                    : l10n.deleteSessionConfirmBody,
                confirmLabel: alive ? l10n.terminate : l10n.delete,
                destructive: true,
              );
              if (!confirmed) return;
              final repo = ref.read(sessionRepositoryProvider);
              if (alive) {
                await repo.terminate(sessionId: session.sessionId);
                await ref
                    .read(sessionControllerProvider.notifier)
                    .closeTerminal(session.sessionId);
              } else {
                await repo.delete(sessionId: session.sessionId);
              }
              ref.invalidate(sessionsProvider);
            },
            backgroundColor: scheme.secondary,
            foregroundColor: scheme.destructive,
            borderRadius: BorderRadius.circular(12),
            autoClose: true,
            icon: LucideIcons.trash2,
          ),
        ],
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            ref
                .read(sessionControllerProvider.notifier)
                .open(session.sessionId, workerId: session.workerId);
            context.go('/workspace');
          },
          child: ShadCard(
          width: double.infinity,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  session.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.small
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              ShadBadge.secondary(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: sessionDotColor(scheme, session.status),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(sessionStatusLabel(context, session.status)),
                  ],
                ),
              ),
            ],
          ),
          description: Text(
            [
              if (session.workerName?.isNotEmpty ?? false) session.workerName!,
              _fmtTime(session.lastActivityAt),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      ),
    );
  }

  String _fmtTime(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year && local.month == now.month && local.day == now.day;
    final hm =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (sameDay) return hm;
    return '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hm';
  }
}

/// 骨架占位条（shadcn_ui 无 Skeleton 组件，最小自绘）。
class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({
    required this.width,
    required this.height,
    this.radius = 4,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: ShadTheme.of(context).colorScheme.muted,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

