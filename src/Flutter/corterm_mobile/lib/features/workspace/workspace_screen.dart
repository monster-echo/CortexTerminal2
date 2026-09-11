import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xterm/xterm.dart';

import '../../app/theme/terminal_theme.dart';
import '../../core/storage/app_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/app_bar.dart';
import '../../shared/widgets/states.dart';
import '../sessions/data/sessions_providers.dart';
import 'widgets/connection_details_sheet.dart';
import 'widgets/more_actions_sheet.dart';
import 'widgets/new_session_sheet.dart';
import 'widgets/session_selector_sheet.dart';
import 'widgets/session_status.dart';
import 'widgets/terminal_toolbar.dart';
import 'workspace_controller.dart';
import 'workspace_state.dart';

/// 主 Terminal 页面（§6/§85）：
///
/// ┌──────────────────────────────────┐
/// │ ‹      SessionName⌄       ●  ⋯  │
/// ├──────────────────────────────────┤
/// │            Terminal              │
/// ├──────────────────────────────────┤
/// │ ESC  TAB  CTRL  ↑  ↓  ⌨          │
/// └──────────────────────────────────┘
///
/// Terminal 占满 AppBar 与工具栏之外的全部空间；无常驻 Context/Status Bar。
class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  @override
  void initState() {
    super.initState();
    // 屏幕常亮（§51）：在监听器里驱动平台通道，禁止 build 内副作用。
    ref.listenManual(workspaceControllerProvider, (_, _) => _applyWakelock());
    _applyWakelock();
  }

  void _applyWakelock() {
    final ws = ref.read(workspaceControllerProvider);
    final entry = ws.entryOf(ws.currentSessionId);
    WakelockPlus.toggle(
      enable:
          ref.read(keepAwakeProvider) && entry?.connState == TerminalConnState.live,
    );
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final ws = ref.watch(workspaceControllerProvider);
    final currentId = ws.currentSessionId;
    final entry = ws.entryOf(currentId);
    final controller = ref.read(workspaceControllerProvider.notifier);

    return Scaffold(
      appBar: _buildAppBar(context, ref, ws, currentId),
      body: entry == null
          ? const _EmptyWorkspace()
          : _TerminalArea(sessionId: currentId!, entry: entry),
      bottomNavigationBar: entry == null
          ? null
          : TerminalToolbar(
              enabled: entry.canInput,
              ctrlArmed: ws.ctrlArmed,
              altArmed: ws.altArmed,
              onKey: controller.sendKey,
              onCtrlToggle: controller.setCtrlArmed,
              onAltToggle: controller.setAltArmed,
              onPaste: controller.sendInputRaw,
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    WorkspaceState ws,
    String? currentId,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final sessions = ref.watch(sessionsProvider);
    final session = sessions.value?.where((s) => s.sessionId == currentId).firstOrNull;
    final entry = ws.entryOf(currentId);
    final scheme = ShadTheme.of(context).colorScheme;

    final (dotColor, pulse) = entry == null
        ? (scheme.mutedForeground, false)
        : connDotStyle(entry.connState);

    return CortermAppBar(
      // 标题 = Session Switcher（§5/§7/§8/§88）：单行、可点击、带下拉指示、自动截断。
      title: l10n.sessions,
      titleWidget: session == null
          ? null
          : InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () =>
                  SessionSelectorSheet.show(context, currentSessionId: ws.currentSessionId),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        session.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: scheme.foreground,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 18, color: scheme.mutedForeground),
                  ],
                ),
              ),
            ),
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: scheme.foreground),
        onPressed: () => context.go('/home'),
      ),
      centerTitle: true,
      actions: [
        if (currentId != null) ...[
          IconButton(
            // 状态圆点（§13）：点击看连接详情（§20）。
            onPressed: () => ConnectionDetailsSheet.show(context, sessionId: currentId),
            icon: _StatusDot(color: dotColor, pulse: pulse),
          ),
          IconButton(
            icon: Icon(Icons.more_horiz_rounded, size: 22, color: scheme.foreground),
            onPressed: () => MoreActionsSheet.show(context, sessionId: currentId),
          ),
          const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color, required this.pulse});

  final Color color;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (!pulse) return dot;
    return _Pulsing(child: dot);
  }
}

class _Pulsing extends StatefulWidget {
  const _Pulsing({required this.child});

  final Widget child;

  @override
  State<_Pulsing> createState() => _PulsingState();
}

class _PulsingState extends State<_Pulsing> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
        child: widget.child,
      );
}

/// 无当前会话（§69）。
class _EmptyWorkspace extends ConsumerWidget {
  const _EmptyWorkspace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return EmptyState(
      title: l10n.noActiveSessions,
      hint: l10n.noActiveSessionsHint,
      actionLabel: l10n.newSession,
      onAction: () => showNewSessionSheet(
        context,
        onCreated: (sessionId) => ref.read(workspaceControllerProvider.notifier).open(sessionId),
      ),
    );
  }
}

/// 终端区域：TerminalView + 轻量状态 banner（§56：不弹重复 Dialog）。
/// 长按选择（vendored xterm 内置）→ 浮出复制按钮（MAUI 同款交互）。
class _TerminalArea extends ConsumerStatefulWidget {
  const _TerminalArea({required this.sessionId, required this.entry});

  final String sessionId;
  final SessionTerminalState entry;

  @override
  ConsumerState<_TerminalArea> createState() => _TerminalAreaState();
}

class _TerminalAreaState extends ConsumerState<_TerminalArea> {
  final _terminalController = TerminalController();

  @override
  void initState() {
    super.initState();
    _terminalController.addListener(_onSelectionChanged);
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _TerminalArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entry.epoch != oldWidget.entry.epoch) {
      // reattach 后 Terminal buffer 已重建，旧 selection 锚点失效。
      _terminalController.clearSelection();
    }
  }

  @override
  void dispose() {
    _terminalController.removeListener(_onSelectionChanged);
    _terminalController.dispose();
    super.dispose();
  }

  Future<void> _copySelection() async {
    final l10n = AppLocalizations.of(context)!;
    final range = _terminalController.selection;
    if (range == null) return;
    final text = widget.entry.terminal.buffer.getText(range);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    _terminalController.clearSelection();
    if (mounted) {
      showAppToast(context, l10n.copied);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fontSize = ref.watch(fontSizeProvider);
    final controller = ref.read(workspaceControllerProvider.notifier);
    final entry = widget.entry;
    final sessionId = widget.sessionId;
    final hasSelection = _terminalController.selection != null;

    final bannerText = switch (entry.connState) {
      TerminalConnState.connecting => l10n.connectBanner,
      TerminalConnState.replaying => l10n.restoringBanner,
      TerminalConnState.reconnecting => l10n.reconnectBanner,
      _ => null,
    };

    return Stack(
      children: [
        Positioned.fill(
          child: TerminalView(
            // epoch 变化（reattach 重放）→ 重建 view，buffer 全新。
            key: ValueKey('term-$sessionId-${entry.epoch}'),
            entry.terminal,
            controller: _terminalController,
            theme: cortermTerminalTheme,
            textStyle: TerminalStyle(fontSize: fontSize),
            readOnly: !entry.canInput,
            autofocus: true,
          ),
        ),
        if (hasSelection)
          Positioned(
            top: 8,
            right: 16,
            child: _CopyButton(onCopy: _copySelection),
          ),
        if (bannerText != null)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(child: _Banner(text: bannerText, busy: true)),
          ),
        if (entry.connState == TerminalConnState.exited ||
            entry.connState == TerminalConnState.error)
          Positioned(
            bottom: 12,
            left: 16,
            right: 16,
            child: _Banner(
              text: entry.connState == TerminalConnState.exited
                  ? l10n.sessionEndedBanner(entry.exitReason ?? '')
                  : entry.errorMessage == 'displaced'
                      ? l10n.displacedBanner
                      : l10n.sessionErrorBanner,
              busy: false,
              onTapReconnect: () => controller.open(sessionId),
              reconnectLabel: l10n.tapToReconnect,
            ),
          ),
      ],
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.onCopy});

  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onCopy,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.copy_rounded, size: 14, color: scheme.background),
              const SizedBox(width: 4),
              Text(
                AppLocalizations.of(context)!.copy,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.background,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    required this.busy,
    this.onTapReconnect,
    this.reconnectLabel,
  });

  final String text;
  final bool busy;
  final VoidCallback? onTapReconnect;
  final String? reconnectLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Material(
      color: scheme.muted.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy) ...[
              const SizedBox(width: 12, height: 12, child: ShadProgress()),
              const SizedBox(width: 8),
            ],
            Text(
              text,
              style: TextStyle(fontSize: 12, color: scheme.foreground),
            ),
            if (onTapReconnect != null) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onTapReconnect,
                child: Text(
                  reconnectLabel!,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
