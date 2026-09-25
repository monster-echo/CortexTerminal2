import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xterm/xterm.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../app/theme/terminal_theme.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../core/models/session.dart';
import '../../../shared/widgets/states.dart';
import '../../sessions/data/sessions_providers.dart';
import '../../workspaces/data/workspace_providers.dart';
import '../session_controller.dart';
import '../session_state.dart';
import 'terminal_keyboard_toolbar.dart';

/// Session 全屏终端页（design/04）：
///
/// Stack
/// ├─ Positioned.fill → TerminalView（不包任何容器）
/// ├─ 左上悬浮返回按钮（退出页面 ≠ 结束会话）
/// ├─ 右上悬浮三点按钮（文件 / 端口转发）
/// ├─ 连接状态 Overlay（条件显示）
/// └─ 底部键盘工具栏（仅软键盘弹出时）
class SessionTerminalScreen extends ConsumerStatefulWidget {
  const SessionTerminalScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<SessionTerminalScreen> createState() =>
      _SessionTerminalScreenState();
}

class _SessionTerminalScreenState extends ConsumerState<SessionTerminalScreen> {
  final _terminalController = TerminalController();

  @override
  void initState() {
    super.initState();
    // 打开 / 附着该 session（已附着时为幂等 no-op）。
    // open 会同步改 provider state，post-frame 执行避免 build 期间修改。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref
          .read(sessionControllerProvider.notifier)
          .open(widget.sessionId));
    });
    // 屏幕常亮（§51）：live 且用户开启 keep-awake 时保持亮屏。
    ref.listenManual(sessionControllerProvider, (_, _) => _applyWakelock());
    _applyWakelock();
    // OSC 扩展事件（52 远程剪贴板 / 9,777 远程通知）→ toast 呈现。
    ref.listenManual(sessionControllerProvider, (prev, next) {
      final notice = next.oscNotice;
      if (notice == null || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showAppToast(
          context,
          notice.kind == OscNoticeKind.clipboard ? '已复制' : notice.message,
        );
        ref.read(sessionControllerProvider.notifier).clearOscNotice();
      });
    });
  }

  void _applyWakelock() {
    final ws = ref.read(sessionControllerProvider);
    final entry = ws.entryOf(widget.sessionId);
    WakelockPlus.toggle(
      enable: ref.read(keepAwakeProvider) &&
          entry?.connState == TerminalConnState.live,
    );
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  void _showMoreMenu(SessionSummary? session) {
    final workspaceId = session?.workspaceId ?? '';
    final workspaces = ref.read(workspacesProvider).value ?? const [];
    final workspace = workspaceId.isEmpty
        ? null
        : workspaces.where((w) => w.workspaceId == workspaceId).firstOrNull;
    final computer = session?.workerName ?? session?.workerId ?? '';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cortermDarkToolTheme().scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetContext) {
        // Modal 路由挂在 Navigator 根上，拿不到页面的 Dark Theme——
        // 显式包一层，否则 colorsOf 解析为 Light token，深色底配深色字对比度极差。
        return Theme(
          data: cortermDarkToolTheme(),
          child: Builder(builder: (sheetContext) {
        final colors = colorsOf(sheetContext);
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 弱信息上下文（design/04 §4）：工作区名 + 电脑名；未绑定工作区只显示电脑名。
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (workspace != null)
                      Text(
                        workspace.displayName,
                        style: TextStyle(
                            fontSize: 13, color: colors.textSecondary),
                      ),
                    Text(
                      computer,
                      style: TextStyle(
                          fontSize: 13, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (workspace != null) ...[
                Divider(height: 1, color: colors.divider),
                _MenuItem(
                  label: '文件',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    final root = workspace.rootPath ?? '/';
                    final name = Uri.encodeComponent(workspace.displayName);
                    context.push(
                      '/workspaces/$workspaceId/files?name=$name&root=${Uri.encodeComponent(root)}',
                    );
                  },
                ),
              ],
              Divider(height: 1, color: colors.divider),
              _MenuItem(
                label: '端口转发',
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('/workspaces/$workspaceId/tunnels');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
          }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(sessionControllerProvider);
    final entry = ws.entryOf(widget.sessionId);
    final sessions = ref.watch(sessionsProvider).value ?? const [];
    final session = sessions
        .where((s) => s.sessionId == widget.sessionId)
        .firstOrNull;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final fontSize = ref.watch(fontSizeProvider);
    // Dark Tool Context 固定深色环境下解析终端配色（followApp → 深色预设）。
    final terminalTheme = resolveTerminalTheme(
      selection: ref.watch(terminalThemeSelectionProvider),
      brightness: Brightness.dark,
      customThemes: ref.watch(customTerminalThemesProvider),
    );

    return Theme(
      data: cortermDarkToolTheme(),
      // Builder：Theme 之内取 colorsOf，保证拿到 Dark Tool tokens。
      child: Builder(builder: (context) {
        final colors = colorsOf(context);
        return Scaffold(
        backgroundColor: colors.background,
        body: entry == null
            ? Center(
                child: Text('正在连接…',
                    style: TextStyle(color: colors.textSecondary)))
            : Stack(
                children: [
                  Positioned.fill(
                    child: TerminalView(
                      // epoch 变化（reattach 重放）→ 重建 view，buffer 全新。
                      key: ValueKey('term-${widget.sessionId}-${entry.epoch}'),
                      entry.terminal,
                      controller: _terminalController,
                      theme: terminalTheme,
                      textStyle: TerminalStyle(
                        fontSize: fontSize,
                        fontFamily: 'packages/shadcn_ui/GeistMono',
                      ),
                      readOnly: !entry.canInput,
                      autofocus: true,
                    ),
                  ),
                  // 左上悬浮返回：退出页面 ≠ 结束会话（design/04 §6）。
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 4,
                    left: 8,
                    child: _FloatingButton(
                      icon: Icons.arrow_back,
                      tooltip: '返回',
                      onTap: () => context.pop(),
                    ),
                  ),
                  // 右上悬浮三点菜单。
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 4,
                    right: 8,
                    child: _FloatingButton(
                      icon: Icons.more_vert,
                      tooltip: '更多',
                      onTap: () => _showMoreMenu(session),
                    ),
                  ),
                  if (entry.connState == TerminalConnState.reconnecting)
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 56,
                      left: 0,
                      right: 0,
                      child: Center(child: _OverlayPill(text: '正在重新连接…')),
                    ),
                  if (entry.connState == TerminalConnState.workerOffline)
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 56,
                      left: 0,
                      right: 0,
                      child: Center(
                          child: _OverlayPill(text: '电脑已离线，等待其上线…')),
                    ),
                  if (_isDead(entry.connState))
                    Positioned(
                      bottom: 24,
                      left: 16,
                      right: 16,
                      child: _DisconnectedCard(
                        entry: entry,
                        onReconnect: () => ref
                            .read(sessionControllerProvider.notifier)
                            .open(widget.sessionId),
                      ),
                    ),
                  // 键盘弹出时才有底部工具栏（design/04 §2/§3）。
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: keyboardOpen
                        ? TerminalKeyboardToolbar(
                            enabled: entry.canInput,
                            ctrlArmed: ws.ctrlArmed,
                            onKey: (seq) => ref
                                .read(sessionControllerProvider.notifier)
                                .sendKey(seq),
                            onCtrlToggle: (armed) => ref
                                .read(sessionControllerProvider.notifier)
                                .setCtrlArmed(armed),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
        );
      }),
    );
  }

  /// 终态：自动重连已失败，需要用户手动重连。
  bool _isDead(TerminalConnState state) =>
      state == TerminalConnState.exited || state == TerminalConnState.error;
}

class _FloatingButton extends StatelessWidget {
  const _FloatingButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    return Material(
      color: colors.surfaceElevated.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(20),
      child: IconButton(
        icon: Icon(icon, size: 20, color: colors.textPrimary),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }
}

/// 轻量状态胶囊（reconnecting overlay，design/04 §5）。
class _OverlayPill extends StatelessWidget {
  const _OverlayPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    return Material(
      color: colors.surfaceElevated.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(text, style: TextStyle(fontSize: 13, color: colors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

/// 断线 / 会话结束卡片（design/04 §5）：文案 + 「重新连接」按钮。
class _DisconnectedCard extends StatelessWidget {
  const _DisconnectedCard({required this.entry, required this.onReconnect});

  final SessionTerminalState entry;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    final dead = entry.connState == TerminalConnState.exited;
    return Material(
      color: colors.surfaceElevated,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              dead ? '连接已结束' : '连接已断开',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary),
            ),
            if (entry.errorMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                entry.errorMessage!,
                style: TextStyle(fontSize: 12, color: colors.danger),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onReconnect,
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: colorsOf(context).onEmphasis,
                minimumSize: const Size.fromHeight(44),
              ),
              child: const Text('重新连接'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 16,
              color: colors.textPrimary),
        ),
      ),
    );
  }
}
