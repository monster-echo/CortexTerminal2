import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/corterm_theme.dart';

/// 键盘辅助工具栏（design/04 §3）：仅在系统键盘弹出时显示。
/// Ctrl 为粘性 latch（吸合期间软键盘字母变控制字符，由 controller 负责）。
class TerminalKeyboardToolbar extends StatelessWidget {
  const TerminalKeyboardToolbar({
    super.key,
    required this.enabled,
    required this.ctrlArmed,
    required this.onKey,
    required this.onCtrlToggle,
  });

  /// 仅 live（附着完成）时可用，防止输入落入未附着的会话。
  final bool enabled;

  /// CTRL 粘性吸合态。
  final bool ctrlArmed;

  /// 直接发送按键序列 / 字符（如 '\x1b'、'\t'、'|'、'/'、'\x1b[A'）。
  final void Function(String seq) onKey;

  /// 切换 CTRL 吸合。
  final void Function(bool armed) onCtrlToggle;

  static const height = 42.0;

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);

    Widget key(String label, VoidCallback onTap, {bool active = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Material(
            color: active
                ? colors.accent.withValues(alpha: 0.22)
                : colors.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: enabled
                  ? () {
                      HapticFeedback.selectionClick();
                      onTap();
                    }
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 34,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: !enabled
                        ? colors.textSecondary.withValues(alpha: 0.4)
                        : active
                            ? colors.accent
                            : colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        );

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            key('Ctrl', () => onCtrlToggle(!ctrlArmed), active: ctrlArmed),
            key('Esc', () => onKey('\x1b')),
            key('Tab', () => onKey('\t')),
            key('|', () => onKey('|')),
            key('/', () => onKey('/')),
            key('↑', () => onKey('\x1b[A')),
            key('↓', () => onKey('\x1b[B')),
            key('←', () => onKey('\x1b[D')),
            key('→', () => onKey('\x1b[C')),
          ],
        ),
      ),
    );
  }
}
