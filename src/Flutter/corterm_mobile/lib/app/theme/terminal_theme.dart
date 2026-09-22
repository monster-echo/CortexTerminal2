import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../core/models/terminal_color_scheme.dart';

/// 内置深/浅预设对应的 xterm TerminalTheme（测试与 followApp 快速路径使用）。
final cortermTerminalDarkTheme =
    _toXtermTheme(builtinTerminalColorSchemes[0]);
final cortermTerminalLightTheme =
    _toXtermTheme(builtinTerminalColorSchemes[1]);

/// 按 selection 解析终端配色：
/// - 'followApp' → 按 App 当前 brightness 落到默认深/浅预设；
/// - 具体档案 id → 在内置 + 自定义里查找，找不到直接抛错（配置错误要显式暴露）。
TerminalTheme resolveTerminalTheme({
  required String selection,
  required Brightness brightness,
  required List<TerminalColorScheme> customThemes,
}) {
  if (selection == followAppTerminalTheme) {
    return brightness == Brightness.dark
        ? cortermTerminalDarkTheme
        : cortermTerminalLightTheme;
  }
  for (final scheme in [...builtinTerminalColorSchemes, ...customThemes]) {
    if (scheme.id == selection) return _toXtermTheme(scheme);
  }
  throw StateError('Unknown terminal theme selection: $selection');
}

/// 档案 → xterm TerminalTheme。searchHit 三色从黄色系/背景派生，不单独建模。
TerminalTheme _toXtermTheme(TerminalColorScheme s) {
  Color hex(String v) => TerminalColorScheme.parseHex(v);
  return TerminalTheme(
    cursor: hex(s.cursor),
    // 档案里 selection 是 6 位 hex；xterm 渲染层统一套 25% 透明度。
    selection: hex(s.selection).withValues(alpha: 0.25),
    foreground: hex(s.foreground),
    background: hex(s.background),
    black: hex(s.black),
    red: hex(s.red),
    green: hex(s.green),
    yellow: hex(s.yellow),
    blue: hex(s.blue),
    magenta: hex(s.magenta),
    cyan: hex(s.cyan),
    white: hex(s.white),
    brightBlack: hex(s.brightBlack),
    brightRed: hex(s.brightRed),
    brightGreen: hex(s.brightGreen),
    brightYellow: hex(s.brightYellow),
    brightBlue: hex(s.brightBlue),
    brightMagenta: hex(s.brightMagenta),
    brightCyan: hex(s.brightCyan),
    brightWhite: hex(s.brightWhite),
    searchHitBackground: hex(s.yellow).withValues(alpha: 0.25),
    searchHitBackgroundCurrent: hex(s.yellow),
    searchHitForeground: hex(s.background),
  );
}
