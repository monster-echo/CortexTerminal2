import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// CortexTerminal dark palette — 1:1 port of the WebView xterm theme
/// (feature/terminal/src/main/resources/rawfile/xterm/index.html).
const cortermTerminalTheme = TerminalTheme(
  cursor: Color(0xFF9FCAFF),
  selection: Color(0xFF3A95E8),
  foreground: Color(0xFFE3E2E2),
  background: Color(0xFF121414),
  black: Color(0xFF3A3D3D),
  red: Color(0xFFFFB4AB),
  green: Color(0xFFA2D489),
  yellow: Color(0xFFFFD180),
  blue: Color(0xFF9FCAFF),
  magenta: Color(0xFFF5A8D0),
  cyan: Color(0xFF80CBC4),
  white: Color(0xFFE3E2E2),
  brightBlack: Color(0xFF8E9192),
  brightRed: Color(0xFFFFB4AB),
  brightGreen: Color(0xFFA2D489),
  brightYellow: Color(0xFFFFD180),
  brightBlue: Color(0xFF9FCAFF),
  brightMagenta: Color(0xFFF5A8D0),
  brightCyan: Color(0xFF80CBC4),
  brightWhite: Color(0xFFE3E2E2),
  searchHitBackground: Color(0xFF3A3D3D),
  searchHitBackgroundCurrent: Color(0xFF3A95E8),
  searchHitForeground: Color(0xFFE3E2E2),
);

/// Scrollback capacity — matches the WebView build's xterm.js config.
const terminalMaxLines = 64000;
