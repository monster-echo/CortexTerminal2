import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Terminal 模块的 dark-only shadcn 主题。
///
/// 色值 = CLAUDE.md `terminal_*` token（深色列），hex 只允许出现在这里。
/// 模块没有 ShadApp（无 Navigator，宿主 ArkTS 侧拥有路由），shadcn 主题由
/// `ShadTheme(data: terminalShadTheme(), child: …)` 按子树注入。
const ShadColorScheme _scheme = ShadColorScheme(
  background: Color(0xFF121414), // 终端画布，与 cortermTerminalTheme.background 一致
  foreground: Color(0xFFe7e9ea), // terminal_primary
  card: Color(0xFF232a3b), // terminal_surface_container（工具条底色）
  cardForeground: Color(0xFFe7e9ea),
  popover: Color(0xFF2d3548), // terminal_surface_container_highest
  popoverForeground: Color(0xFFe7e9ea),
  primary: Color(0xFF7cacf8), // terminal_secondary（工具条动作文字）
  primaryForeground: Color(0xFF0f1419),
  secondary: Color(0xFF1a1f2e), // terminal_surface_container
  secondaryForeground: Color(0xFFe7e9ea),
  muted: Color(0xFF1a1f2e),
  mutedForeground: Color(0xFF9aa4b0), // terminal_on_surface_variant
  accent: Color(0xFF2d3548),
  accentForeground: Color(0xFFe7e9ea),
  destructive: Color(0xFFff5c5c), // terminal_error
  destructiveForeground: Color(0xFFffffff),
  border: Color(0xFF6b7785), // terminal_outline（工具条 1px 分割线）
  input: Color(0xFF6b7785),
  ring: Color(0xFF7cacf8),
  selection: Color(0x407cacf8),
);

/// 工具条动作按钮（ShadButton.ghost）前景 = terminal_secondary 蓝。
ShadThemeData terminalShadTheme() => ShadThemeData(
      brightness: Brightness.dark,
      colorScheme: _scheme,
      ghostButtonTheme: ShadButtonTheme(foregroundColor: _scheme.primary),
    );
