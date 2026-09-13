import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

import 'corterm_theme.dart';
import 'selection_toolbar.dart';
import 'terminal_registry.dart';

/// The single screen of the terminal module: renders the active session's
/// terminal and the selection toolbar. Rebuilds when the registry changes
/// session or replaces a Terminal (reset).
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key, required this.registry});

  final TerminalRegistry registry;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  @override
  void initState() {
    super.initState();
    widget.registry.addListener(_onRegistryChanged);
  }

  void _onRegistryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(TerminalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.registry, widget.registry)) {
      oldWidget.registry.removeListener(_onRegistryChanged);
      widget.registry.addListener(_onRegistryChanged);
    }
  }

  @override
  void dispose() {
    widget.registry.removeListener(_onRegistryChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final terminal = widget.registry.activeTerminal;
    final controller = widget.registry.activeController;
    final sessionId = widget.registry.activeId;

    return ColoredBox(
      color: cortermTerminalTheme.background,
      child: Stack(
        children: [
          if (terminal != null)
            Positioned.fill(
              child: TerminalView(
                // Key on Terminal identity: a reset swaps the object and the
                // view must rebuild from the fresh buffer.
                key: ValueKey<Terminal>(terminal),
                terminal,
                controller: controller,
                autofocus: true,
                textStyle: const TerminalStyle(fontSize: 14),
                theme: cortermTerminalTheme,
                // Parity with the WebView build's cursorStyle: 'bar'.
                cursorType: TerminalCursorType.verticalBar,
                backgroundOpacity: 1,
                padding: const EdgeInsets.all(4),
              ),
            ),
          if (sessionId != null)
            SelectionToolbar(registry: widget.registry, sessionId: sessionId),
        ],
      ),
    );
  }
}
