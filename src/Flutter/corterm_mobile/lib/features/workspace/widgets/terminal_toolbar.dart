import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../l10n/app_localizations.dart';

/// 键盘工具栏（§31/§32）：高度 42，横排可滚动。
/// ESC / TAB / STAB / CTRL(粘性) / ALT(粘性) / 四方向 / HOME / END / 粘贴 / 收键盘。
/// 对齐 MAUI TerminalSessionPage 的按键集合。
class TerminalToolbar extends StatelessWidget {
  const TerminalToolbar({
    super.key,
    required this.enabled,
    required this.ctrlArmed,
    required this.altArmed,
    required this.onKey,
    required this.onCtrlToggle,
    required this.onAltToggle,
    required this.onPaste,
  });

  /// 仅 live 时可用，防止输入落入未附着的会话。
  final bool enabled;
  final bool ctrlArmed;
  final bool altArmed;
  final void Function(String seq) onKey;
  final void Function(bool armed) onCtrlToggle;
  final void Function(bool armed) onAltToggle;
  final void Function(String text) onPaste;

  static const height = 42.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;
    final border = scheme.border;
    final keyStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: enabled ? scheme.foreground : scheme.mutedForeground.withValues(alpha: 0.5),
    );

    Widget key(String label, VoidCallback onTap, {bool active = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Material(
            color: active
                ? scheme.primary.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: enabled
                  ? () {
                      HapticFeedback.selectionClick();
                      onTap();
                    }
                  : null,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  label,
                  style: keyStyle.copyWith(
                    color: active ? scheme.primary : keyStyle.color,
                  ),
                ),
              ),
            ),
          ),
        );

    return Container(
      height: height,
      decoration: BoxDecoration(border: Border(top: BorderSide(color: border))),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  key('ESC', () => onKey('\x1b')),
                  key('TAB', () => onKey('\t')),
                  key('S-TAB', () => onKey('\x1b[Z')),
                  key('CTRL', () => onCtrlToggle(!ctrlArmed), active: ctrlArmed),
                  key('ALT', () => onAltToggle(!altArmed), active: altArmed),
                  key('↑', () => onKey('\x1b[A')),
                  key('↓', () => onKey('\x1b[B')),
                  key('←', () => onKey('\x1b[D')),
                  key('→', () => onKey('\x1b[C')),
                  key('HOME', () => onKey('\x1b[H')),
                  key('END', () => onKey('\x1b[F')),
                  key(l10n.paste, () async {
                    final text = await Clipboard.getData('text/plain');
                    if (text?.text != null && text!.text!.isNotEmpty) {
                      onPaste(text.text!);
                    }
                  }),
                ],
              ),
            ),
          ),
          key('⌨', () => FocusManager.instance.primaryFocus?.unfocus()),
        ],
      ),
    );
  }
}
