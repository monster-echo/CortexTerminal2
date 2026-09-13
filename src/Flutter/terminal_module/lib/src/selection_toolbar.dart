import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:xterm/xterm.dart';

import 'shad_theme.dart';
import 'terminal_registry.dart';

/// Floating copy/select-all/paste bar shown while a selection exists.
///
/// xterm.dart gives us touch-native selection for free (drag = chars,
/// long-press = word, long-press-drag = extend); this only adds the actions.
class SelectionToolbar extends StatefulWidget {
  const SelectionToolbar({
    super.key,
    required this.registry,
    required this.sessionId,
  });

  final TerminalRegistry registry;
  final String? sessionId;

  @override
  State<SelectionToolbar> createState() => _SelectionToolbarState();
}

class _SelectionToolbarState extends State<SelectionToolbar> {
  TerminalController? _listened;

  @override
  void didUpdateWidget(SelectionToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listen();
  }

  void _listen() {
    final controller = widget.registry.activeController;
    if (identical(controller, _listened)) return;
    _listened?.removeListener(_onSelectionChanged);
    _listened = controller;
    _listened?.addListener(_onSelectionChanged);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  bool get _hasSelection {
    final session = _session();
    if (session == null) return false;
    return session.controller.selection != null;
  }

  ({Terminal terminal, TerminalController controller})? _session() {
    final id = widget.sessionId ?? widget.registry.activeId;
    if (id == null) return null;
    final terminal = widget.registry.activeTerminal;
    final controller = widget.registry.activeController;
    if (terminal == null || controller == null) return null;
    return (terminal: terminal, controller: controller);
  }

  Future<void> _copy() async {
    final s = _session();
    final selection = s?.controller.selection;
    if (s == null || selection == null) return;
    await Clipboard.setData(ClipboardData(text: s.terminal.buffer.getText(selection)));
    s.controller.clearSelection();
  }

  Future<void> _selectAll() async {
    final s = _session();
    if (s == null) return;
    final buffer = s.terminal.buffer;
    // Full buffer range: buffer height includes screen + scrollback; the last
    // usable cell is (viewWidth-1, height-1).
    s.controller.setSelection(
      buffer.createAnchor(0, 0),
      buffer.createAnchorFromOffset(
        CellOffset(s.terminal.viewWidth - 1, buffer.height - 1),
      ),
    );
  }

  Future<void> _paste() async {
    final s = _session();
    if (s == null) return;
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    widget.registry.paste(widget.sessionId ?? widget.registry.activeId ?? '', text);
  }

  @override
  void dispose() {
    _listened?.removeListener(_onSelectionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _listen();
    if (!_hasSelection) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 48,
      child: Center(
        // 模块没有 ShadApp，shadcn 主题按子树注入。
        child: ShadTheme(
          data: terminalShadTheme(),
          child: Builder(
            builder: (context) {
              final scheme = ShadTheme.of(context).colorScheme;
              return Container(
                decoration: BoxDecoration(
                  // 原 pill 底色 0xEE232A3B（surface_container + 93% 不透明）
                  color: scheme.card.withValues(alpha: 0xEE / 255),
                  borderRadius: BorderRadius.circular(24),
                  // 替代原 Material elevation: 4
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 8,
                      offset: Offset(0, 2),
                      color: Color(0x66000000),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _action('复制', _copy),
                    _divider(scheme),
                    _action('全选', _selectAll),
                    _divider(scheme),
                    _action('粘贴', _paste),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _action(String label, Future<void> Function() onTap) {
    return ShadButton.ghost(
      onPressed: onTap,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(label, style: const TextStyle(fontSize: 14)),
    );
  }

  Widget _divider(ShadColorScheme scheme) {
    return Container(width: 1, height: 16, color: scheme.border);
  }
}
