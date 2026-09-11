import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'app_theme.dart';

/// 终端主题：始终 Dark（§34，App Shell 可为 Light，Terminal 固定深色）。
final cortermTerminalTheme = TerminalTheme(
  cursor: AppColors.accent,
  selection: const Color(0x402563EB),
  foreground: const Color(0xFFF5F5F5),
  background: const Color(0xFF090909),
  black: const Color(0xFF090909),
  red: const Color(0xFFEF4444),
  green: const Color(0xFF22C55E),
  yellow: const Color(0xFFF59E0B),
  blue: const Color(0xFF3B82F6),
  magenta: const Color(0xFFD946EF),
  cyan: const Color(0xFF06B6D4),
  white: const Color(0xFFF5F5F5),
  brightBlack: const Color(0xFF737373),
  brightRed: const Color(0xFFF87171),
  brightGreen: const Color(0xFF4ADE80),
  brightYellow: const Color(0xFFFBBF24),
  brightBlue: const Color(0xFF60A5FA),
  brightMagenta: const Color(0xFFE879F9),
  brightCyan: const Color(0xFF22D3EE),
  brightWhite: const Color(0xFFFFFFFF),
  searchHitBackground: const Color(0x40F59E0B),
  searchHitBackgroundCurrent: const Color(0xFFF59E0B),
  searchHitForeground: const Color(0xFF090909),
);
