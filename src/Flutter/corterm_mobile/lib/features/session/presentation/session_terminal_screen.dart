import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xterm/xterm.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../app/theme/terminal_theme.dart';
import '../../../l10n/app_localizations.dart';
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
      unawaited(
        ref.read(sessionControllerProvider.notifier).open(widget.sessionId),
      );
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
          notice.kind == OscNoticeKind.clipboard
              ? AppLocalizations.of(context)!.copied
              : notice.message,
        );
        ref.read(sessionControllerProvider.notifier).clearOscNotice();
      });
    });
  }

  void _applyWakelock() {
    final ws = ref.read(sessionControllerProvider);
    final entry = ws.entryOf(widget.sessionId);
    WakelockPlus.toggle(
      enable:
          ref.read(keepAwakeProvider) &&
          entry?.connState == TerminalConnState.live,
    );
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  ThemeData _pageTheme() => terminalPageTheme(
    resolveTerminalTheme(
      selection: ref.read(terminalThemeSelectionProvider),
      brightness: Theme.of(context).brightness,
      customThemes: ref.read(customTerminalThemesProvider),
    ),
  );

  void _showMoreMenu(SessionSummary? session) {
    final l10n = AppLocalizations.of(context)!;
    final workspaceId = session?.workspaceId ?? '';
    final workspaces = ref.read(workspacesProvider).value ?? const [];
    final workspace = workspaceId.isEmpty
        ? null
        : workspaces.where((w) => w.workspaceId == workspaceId).firstOrNull;
    final computer = session?.workerName ?? session?.workerId ?? '';

    showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 280),
        reverseDuration: Duration(milliseconds: 220),
      ),
      backgroundColor: _pageTheme().scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetContext) {
        // Modal 路由挂在 Navigator 根上，拿不到页面的 Dark Theme——
        // 显式包一层，否则 colorsOf 解析为 Light token，深色底配深色字对比度极差。
        return Theme(
          data: _pageTheme(),
          child: Builder(
            builder: (sheetContext) {
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
                                fontSize: 13,
                                color: colors.textSecondary,
                              ),
                            ),
                          Text(
                            computer,
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (workspace != null) ...[
                      Divider(height: 1, color: colors.divider),
                      _MenuItem(
                        label: l10n.files,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          final root = workspace.rootPath ?? '/';
                          final name = Uri.encodeComponent(
                            workspace.displayName,
                          );
                          context.push(
                            '/workspaces/$workspaceId/files?name=$name&root=${Uri.encodeComponent(root)}',
                          );
                        },
                      ),
                    ],
                    Divider(height: 1, color: colors.divider),
                    _MenuItem(
                      label: l10n.forkSession,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _forkSession(session);
                      },
                    ),
                    Divider(height: 1, color: colors.divider),
                    _MenuItem(
                      label: l10n.copyAllOutput,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _copyAllOutput();
                      },
                    ),
                    if (workspace != null) ...[
                      Divider(height: 1, color: colors.divider),
                      _MenuItem(
                        label: l10n.portForwardingTitle,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          context.push('/workspaces/$workspaceId/tunnels');
                        },
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Fork：以当前会话为模板新建 shell（同 worker + OSC 7 实时 cwd）。
  /// 失败（cwd 未上报 / 创建失败）原样 toast 展示，不静默回退。
  Future<void> _forkSession(SessionSummary? session) async {
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .forkSession(widget.sessionId, sourceName: session?.name ?? '');
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '$e', destructive: true);
    }
  }

  void _showSessionSwitcher() {
    final sessions = ref.read(sessionsProvider).asData?.value ?? const [];
    final theme = _pageTheme();
    showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 280),
        reverseDuration: Duration(milliseconds: 220),
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      showDragHandle: true,
      builder: (sheetContext) => Theme(
        data: theme,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .62,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    AppLocalizations.of(context)!.sessions,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colorsOf(sheetContext).textPrimary,
                    ),
                  ),
                ),
                for (final item in sessions)
                  ListTile(
                    leading: Icon(
                      item.status.isRunning
                          ? Icons.circle
                          : Icons.circle_outlined,
                      size: 9,
                      color: item.status.isRunning
                          ? colorsOf(sheetContext).success
                          : colorsOf(sheetContext).textSecondary,
                    ),
                    title: Text(item.displayName),
                    subtitle: Text(item.status.name),
                    trailing: item.sessionId == widget.sessionId
                        ? Icon(
                            Icons.check,
                            color: colorsOf(sheetContext).accent,
                          )
                        : null,
                    onTap: item.sessionId == widget.sessionId
                        ? null
                        : () {
                            Navigator.pop(sheetContext);
                            context.pushReplacement(
                              '/sessions/${item.sessionId}',
                            );
                          },
                  ),
                if (sessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      AppLocalizations.of(context)!.noSessions,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colorsOf(sheetContext).textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 复制当前 buffer 全部文本到系统剪贴板。
  void _copyAllOutput() {
    try {
      final text = ref
          .read(sessionControllerProvider.notifier)
          .bufferText(widget.sessionId);
      Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      showAppToast(context, AppLocalizations.of(context)!.copied);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '$e', destructive: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ws = ref.watch(sessionControllerProvider);
    final entry = ws.entryOf(widget.sessionId);
    final sessions = ref.watch(sessionsProvider).asData?.value ?? const [];
    final session = sessions
        .where((s) => s.sessionId == widget.sessionId)
        .firstOrNull;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final fontSize = ref.watch(fontSizeProvider);
    // 跟随应用时使用应用亮度；自定义主题覆盖终端整页及系统栏。
    final terminalTheme = resolveTerminalTheme(
      selection: ref.watch(terminalThemeSelectionProvider),
      brightness: Theme.of(context).brightness,
      customThemes: ref.watch(customTerminalThemesProvider),
    );

    final pageTheme = terminalPageTheme(terminalTheme);
    final dark = pageTheme.brightness == Brightness.dark;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          FocusManager.instance.primaryFocus?.unfocus(
            disposition: UnfocusDisposition.scope,
          );
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: terminalTheme.background,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: dark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: terminalTheme.background,
          systemNavigationBarIconBrightness: dark
              ? Brightness.light
              : Brightness.dark,
        ),
        child: Theme(
          data: pageTheme,
          // Theme 内解析由终端颜色派生的页面 tokens。
          child: Builder(
            builder: (context) {
              final colors = colorsOf(context);
              return Scaffold(
                backgroundColor: colors.background,
                resizeToAvoidBottomInset: true,
                body: SafeArea(
                  top: true,
                  bottom: false,
                  child: Column(
                    children: [
                      _TerminalHeader(
                        title: session?.name ?? l10n.connConnecting,
                        status: switch (entry?.connState) {
                          null ||
                          TerminalConnState.idle ||
                          TerminalConnState.connecting ||
                          TerminalConnState.replaying => l10n.connConnecting,
                          TerminalConnState.live =>
                            entry!.rttMs != null
                                ? '${entry.rttMs}ms'
                                : l10n.connLive,
                          TerminalConnState.reconnecting =>
                            l10n.connReconnecting,
                          TerminalConnState.workerOffline =>
                            l10n.computerOfflineWaiting,
                          TerminalConnState.exited => l10n.statusExited,
                          TerminalConnState.error => l10n.sessionErrorBanner,
                        },
                        statusColor: entry?.connState == TerminalConnState.live
                            ? colors.success
                            : _isDead(
                                entry?.connState ?? TerminalConnState.idle,
                              )
                            ? colors.danger
                            : colors.warning,
                        onBack: () {
                          FocusManager.instance.primaryFocus?.unfocus(
                            disposition: UnfocusDisposition.scope,
                          );
                          context.pop();
                        },
                        onSwitch: () => _showSessionSwitcher(),
                        onMore: () => _showMoreMenu(session),
                      ),
                      Expanded(
                        child: entry == null
                            ? Center(
                                child: Text(
                                  l10n.connConnecting,
                                  style: TextStyle(color: colors.textSecondary),
                                ),
                              )
                            : Stack(
                                children: [
                                  Positioned.fill(
                                    child: TerminalView(
                                      // epoch 变化（reattach 重放）→ 重建 view，buffer 全新。
                                      key: ValueKey(
                                        'term-${widget.sessionId}-${entry.epoch}',
                                      ),
                                      entry.terminal,
                                      controller: _terminalController,
                                      theme: terminalTheme,
                                      textStyle: TerminalStyle(
                                        fontSize: fontSize,
                                        fontFamily:
                                            'packages/shadcn_ui/GeistMono',
                                      ),
                                      readOnly: !entry.canInput,
                                      autofocus: true,
                                    ),
                                  ),
                                  if (entry.connState ==
                                      TerminalConnState.reconnecting)
                                    Positioned(
                                      top:
                                          MediaQuery.paddingOf(context).top +
                                          56,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: _OverlayPill(
                                          text: l10n.connReconnecting,
                                        ),
                                      ),
                                    ),
                                  if (entry.connState ==
                                      TerminalConnState.workerOffline)
                                    Positioned(
                                      top:
                                          MediaQuery.paddingOf(context).top +
                                          56,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: _OverlayPill(
                                          text: l10n.computerOfflineWaiting,
                                        ),
                                      ),
                                    ),
                                  if (_isDead(entry.connState))
                                    Positioned(
                                      bottom: 24,
                                      left: 16,
                                      right: 16,
                                      child: _DisconnectedCard(
                                        entry: entry,
                                        onReconnect: () => ref
                                            .read(
                                              sessionControllerProvider
                                                  .notifier,
                                            )
                                            .open(widget.sessionId),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                      if (keyboardOpen && entry != null)
                        TerminalKeyboardToolbar(
                          enabled: entry.canInput,
                          ctrlArmed: ws.ctrlArmed,
                          altArmed: ws.altArmed,
                          onKey: (seq) => ref
                              .read(sessionControllerProvider.notifier)
                              .sendKey(seq),
                          onCtrlToggle: (armed) => ref
                              .read(sessionControllerProvider.notifier)
                              .setCtrlArmed(armed),
                          onAltToggle: (armed) => ref
                              .read(sessionControllerProvider.notifier)
                              .setAltArmed(armed),
                          onPaste: () async {
                            if (!entry.canInput) return;
                            final clipboard = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
                            final text = clipboard?.text;
                            if (text != null && text.isNotEmpty) {
                              if (ws.ctrlArmed || ws.altArmed) {
                                ref
                                    .read(sessionControllerProvider.notifier)
                                    .sendKey(text);
                              } else {
                                // Terminal.paste honors xterm bracketed-paste mode.
                                entry.terminal.paste(text);
                              }
                            }
                          },
                          onDone: () => FocusManager.instance.primaryFocus
                              ?.unfocus(disposition: UnfocusDisposition.scope),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 终态：自动重连已失败，需要用户手动重连。
  bool _isDead(TerminalConnState state) =>
      state == TerminalConnState.exited || state == TerminalConnState.error;
}

class _TerminalHeader extends StatelessWidget {
  const _TerminalHeader({
    required this.title,
    required this.status,
    required this.statusColor,
    required this.onBack,
    required this.onSwitch,
    required this.onMore,
  });

  final String title;
  final String status;
  final Color statusColor;
  final VoidCallback onBack;
  final VoidCallback onSwitch;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: onBack,
            icon: Icon(Icons.chevron_left, color: c.textPrimary, size: 24),
          ),
          Expanded(
            child: InkWell(
              onTap: onSwitch,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(Icons.expand_more, color: c.textSecondary, size: 18),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  status,
                  style: TextStyle(color: statusColor, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context)!.more,
            onPressed: onMore,
            icon: Icon(Icons.more_vert, color: c.textPrimary),
          ),
        ],
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
            Text(
              text,
              style: TextStyle(fontSize: 13, color: colors.textPrimary),
            ),
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
    final l10n = AppLocalizations.of(context)!;
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
              dead ? l10n.sessionEnded : l10n.connClosed,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
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
                backgroundColor: colors.emphasis,
                foregroundColor: colors.onEmphasis,
                minimumSize: const Size.fromHeight(44),
              ),
              child: Text(l10n.reconnectAction),
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
          style: TextStyle(fontSize: 16, color: colors.textPrimary),
        ),
      ),
    );
  }
}
