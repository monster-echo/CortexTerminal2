/// shadcn 组件层映射到 Harmony ArkTS 的 terminal_* 主题 token。
///
/// 唯一允许出现 hex 的地方。组件一律从 `ShadTheme.of(context)` 取色；
/// 状态色（success/warning/idle）走官方 colorScheme.custom 槽，与品牌色分离。
/// 字阶用包内置 Geist textTheme（h1Large..muted），页面禁止内联 fontSize。
library;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 品牌蓝（无 context 场景专用：终端光标等）。页面代码不要引用。
class CortermBrand {
  static const light = Color(0xFF0369A1);
  static const dark = Color(0xFF7DD3FC);
}

/// 状态色访问：`scheme.success` / `scheme.warning` / `scheme.idle`。
/// 一个语义一个色：绿=Live/Success，琥珀=Waiting/Recovering，灰=Idle/Ended。
extension CortermStatusColors on ShadColorScheme {
  Color get success => custom['success']!;
  Color get warning => custom['warning']!;
  Color get idle => custom['idle']!;
}

ShadColorScheme _scheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final base = light
      ? const ShadZincColorScheme.light()
      : const ShadZincColorScheme.dark();
  // 颜色与 Harmony common/core resources/{light,dark}/element/color.json 同源。
  return base.copyWith(
    background: light ? const Color(0xFFF8FAFC) : const Color(0xFF0F1419),
    foreground: light ? const Color(0xFF111827) : const Color(0xFFE5E7EB),
    card: light ? const Color(0xFFFFFFFF) : const Color(0xFF161B22),
    cardForeground: light ? const Color(0xFF111827) : const Color(0xFFE5E7EB),
    popover: light ? const Color(0xFFFFFFFF) : const Color(0xFF161B22),
    popoverForeground: light
        ? const Color(0xFF111827)
        : const Color(0xFFE5E7EB),
    primary: light ? const Color(0xFF111827) : const Color(0xFFF8FAFC),
    primaryForeground: light
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF111827),
    secondary: light ? const Color(0xFFEEF2F6) : const Color(0xFF232B36),
    secondaryForeground: light
        ? const Color(0xFF37414D)
        : const Color(0xFFE5E7EB),
    muted: light ? const Color(0xFFEEF2F6) : const Color(0xFF1F2937),
    mutedForeground: light ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
    accent: light ? const Color(0xFFE0F2FE) : const Color(0xFF1E3252),
    accentForeground: light ? const Color(0xFF0C4A6E) : const Color(0xFFB7D9F2),
    destructive: light ? const Color(0xFFB91C1C) : const Color(0xFFFCA5A5),
    destructiveForeground: light
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF0F172A),
    border: light ? const Color(0xFFCBD5E1) : const Color(0xFF3B4450),
    input: light ? const Color(0xFFCBD5E1) : const Color(0xFF3B4450),
    ring: light ? const Color(0xFF0284C7) : const Color(0xFF7DD3FC),
    selection: light ? const Color(0xFFE0F2FE) : const Color(0xFF30363D),
    custom: {
      'success': light ? const Color(0xFF15803D) : const Color(0xFF86EFAC),
      'warning': light ? const Color(0xFFA16207) : const Color(0xFFFBBF24),
      'idle': light ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
    },
  );
}

/// Light/Dark shadcn 主题（ShadApp 直接消费）。
/// Harmony 配色 token + 移动端圆角 10、
/// 移动端触控尺寸修正（shadcn web 默认 40 太矮）。
ShadThemeData shadLightTheme() => ShadThemeData(
  brightness: Brightness.light,
  colorScheme: _scheme(Brightness.light),
  radius: const BorderRadius.all(Radius.circular(10)),
  buttonSizesTheme: const ShadButtonSizesTheme(
    regular: ShadButtonSizeTheme(
      height: 44,
      padding: EdgeInsets.symmetric(horizontal: 16),
    ),
    sm: ShadButtonSizeTheme(
      height: 40,
      padding: EdgeInsets.symmetric(horizontal: 12),
    ),
    lg: ShadButtonSizeTheme(
      height: 48,
      padding: EdgeInsets.symmetric(horizontal: 20),
    ),
    icon: ShadButtonSizeTheme(height: 44, width: 44, padding: EdgeInsets.zero),
  ),
);

ShadThemeData shadDarkTheme() => ShadThemeData(
  brightness: Brightness.dark,
  colorScheme: _scheme(Brightness.dark),
  radius: const BorderRadius.all(Radius.circular(10)),
  buttonSizesTheme: const ShadButtonSizesTheme(
    regular: ShadButtonSizeTheme(
      height: 44,
      padding: EdgeInsets.symmetric(horizontal: 16),
    ),
    sm: ShadButtonSizeTheme(
      height: 40,
      padding: EdgeInsets.symmetric(horizontal: 12),
    ),
    lg: ShadButtonSizeTheme(
      height: 48,
      padding: EdgeInsets.symmetric(horizontal: 20),
    ),
    icon: ShadButtonSizeTheme(height: 44, width: 44, padding: EdgeInsets.zero),
  ),
);
