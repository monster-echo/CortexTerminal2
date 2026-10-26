import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/storage/app_preferences.dart' show terminalKeyDefaults;

/// Matches ArkTS VirtualKeyBar: Esc, sticky modifiers, Tab variants, arrows,
/// Paste, and a fixed Done button while the system keyboard is visible.
class TerminalKeyboardToolbar extends StatelessWidget {
  const TerminalKeyboardToolbar({
    super.key,
    required this.enabled,
    required this.ctrlArmed,
    required this.altArmed,
    required this.onKey,
    required this.onCtrlToggle,
    required this.onAltToggle,
    required this.onPaste,
    required this.onDone,
    this.keyLayout = terminalKeyDefaults,
  });

  final List<String> keyLayout;
  final bool enabled;
  final bool ctrlArmed;
  final bool altArmed;
  final void Function(String seq) onKey;
  final void Function(bool armed) onCtrlToggle;
  final void Function(bool armed) onAltToggle;
  final VoidCallback onPaste;
  final VoidCallback onDone;

  static const height = 44.0;

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    final l10n = AppLocalizations.of(context)!;

    Widget key(String label, VoidCallback action, {bool active = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Material(
            color: active ? colors.surfaceSelected : colors.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: enabled
                  ? () {
                      HapticFeedback.selectionClick();
                      action();
                    }
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: const BoxConstraints(minWidth: 36),
                height: 36,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
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
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  for (final id in keyLayout)
                    switch (id) {
                      'esc' => key('Esc', () => onKey('\x1b')),
                      'ctrl' => key(
                        'Ctrl',
                        () => onCtrlToggle(!ctrlArmed),
                        active: ctrlArmed,
                      ),
                      'alt' => key(
                        'Alt',
                        () => onAltToggle(!altArmed),
                        active: altArmed,
                      ),
                      'tab' => key('Tab', () => onKey('\t')),
                      'shiftTab' => key('S-Tab', () => onKey('\x1b[Z')),
                      'left' => key('←', () => onKey('\x1b[D')),
                      'up' => key('↑', () => onKey('\x1b[A')),
                      'down' => key('↓', () => onKey('\x1b[B')),
                      'right' => key('→', () => onKey('\x1b[C')),
                      'paste' => key(l10n.paste, onPaste),
                      _ => throw StateError('Unknown terminal key: $id'),
                    },
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 4),
            child: Material(
              color: colors.emphasis,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onDone();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 52),
                  height: 36,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    l10n.done,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.onEmphasis,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
