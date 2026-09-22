import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xterm/xterm.dart';

import '../../app/theme/terminal_theme.dart';
import '../../app/theme/app_theme.dart';
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
    // OSC 扩展事件（52 远程剪贴板 / 9,777 远程通知）→ toast 呈现。
    ref.listenManual(workspaceControllerProvider, (prev, next) {
      final notice = next.oscNotice;
      if (notice == null || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final l10n = AppLocalizations.of(context)!;
        showAppToast(
          context,
          notice.kind == OscNoticeKind.clipboard
              ? l10n.copied
              : notice.message,
        );
        ref.read(workspaceControllerProvider.notifier).clearOscNotice();
      });
    });
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
    // 键盘工具栏在软键盘弹出时出现（对齐 ArkTS VirtualKeyBar 行为）；
    // 收起键盘（收起键 / 系统返回）→ viewInsets 归零 → 工具栏随动画收回。
    // web 没有软键盘概念（viewInsets 恒为 0，输入靠物理键盘）→ 工具栏常驻，
    // 作为 ESC/方向键/粘贴的快捷条（桌面终端同形态）。
    final keyboardOpen =
        kIsWeb || MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      appBar: _buildAppBar(context, ref, ws, currentId),
      // 工具栏必须放在 body 内：Scaffold 的 bottomNavigationBar 定位在屏幕物理底部
      // （键盘只压缩 body，不推 bottomNavigationBar），放那里会被键盘完全遮住。
      // body 已被 viewInsets 压缩，Column 末尾即键盘上方。
      body: entry == null
          ? const _EmptyWorkspace()
          : Column(
              children: [
                Expanded(
                  child: _TerminalArea(sessionId: currentId!, entry: entry),
                ),
                _CollapsibleToolbar(
                  visible: keyboardOpen,
                  child: TerminalToolbar(
                    enabled: entry.canInput,
                    ctrlArmed: ws.ctrlArmed,
                    altArmed: ws.altArmed,
                    onKey: controller.sendKey,
                    onCtrlToggle: controller.setCtrlArmed,
                    onAltToggle: controller.setAltArmed,
                    onPaste: controller.sendInputRaw,
                  ),
                ),
              ],
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
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;

    final (dotColor, pulse) = entry == null
        ? (scheme.mutedForeground, false)
        : connDotStyle(scheme, entry.connState);

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
                        // 远端 OSC 标题优先（对齐 ArkTS 动态标题）；无则用会话名。
                        (entry?.remoteTitle?.isNotEmpty ?? false)
                            ? entry!.remoteTitle!
                            : session.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.small.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.foreground,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(LucideIcons.chevronDown,
                        size: 18, color: scheme.mutedForeground),
                  ],
                ),
              ),
            ),
      leading: ShadIconButton.ghost(
        foregroundColor: scheme.foreground,
        icon: const Icon(LucideIcons.arrowLeft, size: 20),
        onPressed: () => context.go('/home'),
      ),
      centerTitle: true,
      actions: [
        if (currentId != null) ...[
          // 状态徽章（对齐 ArkTS TerminalPage）：点数 + 延迟值/状态词，点击看连接详情。
          _StatusBadge(
            entry: entry,
            fallbackColor: dotColor,
            pulse: pulse,
            onTap: () => ConnectionDetailsSheet.show(context, sessionId: currentId),
          ),
          ShadIconButton.ghost(
            foregroundColor: scheme.foreground,
            icon: Icon(LucideIcons.ellipsis, size: 22),
            onPressed: () => MoreActionsSheet.show(context, sessionId: currentId),
          ),
        ],
      ],
    );
  }
}

/// 终端顶栏状态徽章：胶囊底（muted）+ 状态点 + 文案。
/// Live 态显示实时延迟（>300ms 红、>100ms 琥珀、其余绿，ArkTS 同规则）；
/// 其余态显示状态词；error/exited 文字用 destructive。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.entry,
    required this.fallbackColor,
    required this.pulse,
    required this.onTap,
  });

  final SessionTerminalState? entry;
  final Color fallbackColor;
  final bool pulse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;
    final state = entry?.connState;
    final rtt = entry?.rttMs;

    Color rttColor(int ms) {
      if (ms > 300) return scheme.destructive;
      if (ms > 100) return scheme.warning;
      return scheme.success;
    }

    final live = state == TerminalConnState.live;
    final dotColor = live && rtt != null ? rttColor(rtt) : fallbackColor;
    final label = live && rtt != null
        ? '$rtt ms'
        : switch (state) {
            TerminalConnState.live => l10n.connLive,
            TerminalConnState.connecting => l10n.connConnecting,
            TerminalConnState.replaying => l10n.connReplaying,
            TerminalConnState.reconnecting => l10n.connReconnecting,
            TerminalConnState.idle => l10n.connIdle,
            TerminalConnState.exited => l10n.connExited,
            TerminalConnState.error => l10n.connError,
            null => l10n.connIdle,
          };
    final textColor =
        state == TerminalConnState.error || state == TerminalConnState.exited
            ? scheme.destructive
            : scheme.mutedForeground;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: scheme.muted,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusDot(color: dotColor, pulse: pulse),
            const SizedBox(width: 6),
            Text(
              label,
              style: ShadTheme.of(context)
                  .textTheme
                  .muted
                  .copyWith(fontSize: 12, color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// 键盘工具栏的出现/收起动画：高度随 `heightFactor` 折叠（与系统键盘动画同节奏），
/// 内容同步淡入淡出。收起后高度为 0，不占布局空间。
class _CollapsibleToolbar extends StatelessWidget {
  const _CollapsibleToolbar({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedAlign(
        alignment: Alignment.bottomCenter,
        heightFactor: visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: child,
        ),
      ),
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

  /// 长按触点（屏幕坐标）。选择存在时用于锚定浮动菜单；取消选择即清除。
  Offset? _menuAnchorGlobal;

  /// expired/exited 2 秒后自动回首页（对齐 ArkTS TerminalPage 收尾行为）。
  Timer? _autoReturnTimer;

  @override
  void initState() {
    super.initState();
    _terminalController.addListener(_onSelectionChanged);
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    // 选择被外部清除（点终端、双击重选等）→ 菜单一并消失。
    if (_terminalController.selection == null && _menuAnchorGlobal != null) {
      setState(() => _menuAnchorGlobal = null);
    } else {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant _TerminalArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entry.epoch != oldWidget.entry.epoch) {
      // reattach 后 Terminal buffer 已重建，旧 selection 锚点失效。
      _terminalController.clearSelection();
      _menuAnchorGlobal = null;
    }
    // 会话退出：2 秒后关闭本地终端并回首页（error 态保留在页面供重试）。
    if (widget.entry.connState == TerminalConnState.exited &&
        oldWidget.entry.connState != TerminalConnState.exited) {
      _autoReturnTimer?.cancel();
      final sessionId = widget.sessionId;
      _autoReturnTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        ref.read(workspaceControllerProvider.notifier).closeTerminal(sessionId);
        context.go('/home');
      });
    }
  }

  @override
  void dispose() {
    _autoReturnTimer?.cancel();
    _terminalController.removeListener(_onSelectionChanged);
    _terminalController.dispose();
    super.dispose();
  }

  void _onLongPress(LongPressStartDetails details) {
    HapticFeedback.mediumImpact();
    setState(() => _menuAnchorGlobal = details.globalPosition);
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
      HapticFeedback.selectionClick();
      showAppToast(context, l10n.copied);
    }
  }

  /// 全选回滚区（与 vendored xterm SelectAllTextIntent 同一算法）。
  void _selectAll() {
    final terminal = widget.entry.terminal;
    _terminalController.setSelection(
      terminal.buffer.createAnchor(0, terminal.buffer.height - terminal.viewHeight),
      terminal.buffer.createAnchor(terminal.viewWidth, terminal.buffer.height - 1),
      mode: SelectionMode.line,
    );
    HapticFeedback.selectionClick();
  }

  /// 粘贴走 terminal.paste：自动带 bracketed-paste 包裹（与系统粘贴意图一致）。
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    widget.entry.terminal.paste(text);
    _terminalController.clearSelection();
    HapticFeedback.selectionClick();
  }

  void _dismissMenu() {
    _terminalController.clearSelection();
    HapticFeedback.selectionClick();
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // 终端配色：followApp 跟随 App 深浅；具体主题按档案解析。
        final terminalTheme = resolveTerminalTheme(
          selection: ref.watch(terminalThemeSelectionProvider),
          brightness: Theme.of(context).brightness,
          customThemes: ref.watch(customTerminalThemesProvider),
        );
        // 屏幕坐标 → 终端区局部坐标（菜单锚点）。
        Offset? menuAnchorLocal;
        final box = context.findRenderObject();
        if (hasSelection && _menuAnchorGlobal != null && box is RenderBox) {
          menuAnchorLocal = box.globalToLocal(_menuAnchorGlobal!);
        }

        return Stack(
          children: [
            Positioned.fill(
              child: TerminalView(
                // epoch 变化（reattach 重放）→ 重建 view，buffer 全新。
                key: ValueKey('term-$sessionId-${entry.epoch}'),
                entry.terminal,
                controller: _terminalController,
                theme: terminalTheme,
                // 显式等宽字体：web（CanvasKit）没有系统 monospace 可回退，
                // 默认 'monospace' 会掉到非等宽字体导致字符网格错位。
                // GeistMono 随 shadcn_ui 包内置，三端一致。
                textStyle: TerminalStyle(
                  fontSize: fontSize,
                  fontFamily: 'packages/shadcn_ui/GeistMono',
                ),
                readOnly: !entry.canInput,
                autofocus: true,
                onLongPressStart: _onLongPress,
              ),
            ),
            if (hasSelection && menuAnchorLocal != null)
              _SelectionMenu(
                anchor: menuAnchorLocal,
                areaSize: constraints.biggest,
                onCopy: _copySelection,
                onSelectAll: _selectAll,
                onPaste: _pasteFromClipboard,
                onCancel: _dismissMenu,
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
      },
    );
  }
}

/// 长按选择浮动菜单（复制 / 全选 / 粘贴 / 取消）。
///
/// 定位规则对齐 ArkTS TerminalPage：默认在触点上方（间隙 12），横向以触点为中心，
/// 8px 边距内夹紧；上方放不下时落到触点下方。首帧隐藏、量完尺寸再显示，避免溢出闪动。
class _SelectionMenu extends StatefulWidget {
  const _SelectionMenu({
    required this.anchor,
    required this.areaSize,
    required this.onCopy,
    required this.onSelectAll,
    required this.onPaste,
    required this.onCancel,
  });

  final Offset anchor;
  final Size areaSize;
  final VoidCallback onCopy;
  final VoidCallback onSelectAll;
  final VoidCallback onPaste;
  final VoidCallback onCancel;

  @override
  State<_SelectionMenu> createState() => _SelectionMenuState();
}

class _SelectionMenuState extends State<_SelectionMenu> {
  final _menuKey = GlobalKey();
  bool _placed = false;
  double _left = 0;
  double _top = 0;

  static const _gap = 12.0;
  static const _margin = 8.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _place());
  }

  void _place() {
    final box = _menuKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !mounted) return;
    final size = box.size;
    var left = widget.anchor.dx - size.width / 2;
    left = left.clamp(_margin, (widget.areaSize.width - _margin - size.width).clamp(_margin, double.infinity));
    var top = widget.anchor.dy - size.height - _gap;
    if (top < _margin) top = widget.anchor.dy + _gap; // 触点在顶部 → 放下方
    top = top.clamp(_margin, (widget.areaSize.height - _margin - size.height).clamp(_margin, double.infinity));
    setState(() {
      _left = left;
      _top = top;
      _placed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;

    Widget item(IconData icon, String label, VoidCallback onTap) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: scheme.foreground),
                const SizedBox(width: 5),
                Text(label, style: ShadTheme.of(context).textTheme.small),
              ],
            ),
          ),
        ),
      );
    }

    Widget divider() => Container(
          width: 1,
          height: 16,
          margin: const EdgeInsets.symmetric(vertical: 6),
          color: scheme.border,
        );

    return Positioned(
      left: _left,
      top: _top,
      child: AnimatedOpacity(
        opacity: _placed ? 1 : 0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          key: _menuKey,
          decoration: BoxDecoration(
            color: scheme.popover,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.border),
            boxShadow: [
              BoxShadow(
                color: scheme.foreground.withValues(alpha: 0.10),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              item(LucideIcons.copy, l10n.copy, widget.onCopy),
              divider(),
              item(LucideIcons.textCursor, l10n.selectAll, widget.onSelectAll),
              divider(),
              item(LucideIcons.clipboardPaste, l10n.paste, widget.onPaste),
              divider(),
              item(LucideIcons.x, l10n.cancel, widget.onCancel),
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
              style: ShadTheme.of(context).textTheme.small.copyWith(color: scheme.foreground),
            ),
            if (onTapReconnect != null) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onTapReconnect,
                child: Text(
                  reconnectLabel!,
                  style: ShadTheme.of(context).textTheme.small.copyWith(
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
