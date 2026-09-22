/// 设计基座：官方 shadcn zinc 色板（黑白灰）。
///
/// 唯一允许出现 hex 的地方。组件一律从 `ShadTheme.of(context)` 取色；
/// 状态色（success/warning/idle）走官方 colorScheme.custom 槽，与品牌色分离。
/// 字阶用包内置 Geist textTheme（h1Large..muted），页面禁止内联 fontSize。
library;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 品牌蓝（无 context 场景专用：终端光标等）。页面代码不要引用。
class CortermBrand {
  static const light = Color(0xFF2563EB); // tailwind blue-600
  static const dark = Color(0xFF3B82F6); // tailwind blue-500
}

/// 状态色访问：`scheme.success` / `scheme.warning` / `scheme.idle`。
/// 一个语义一个色：绿=Live/Success，琥珀=Waiting/Recovering，灰=Idle/Ended。
extension CortermStatusColors on ShadColorScheme {
  Color get success => custom['success']!;
  Color get warning => custom['warning']!;
  Color get idle => custom['idle']!;
}

ShadColorScheme _scheme(Brightness brightness) {
  final base = brightness == Brightness.light
      ? const ShadZincColorScheme.light()
      : const ShadZincColorScheme.dark();
  // shadcn 原生 zinc：primary = foreground（近黑/近白），黑白灰观感。
  // 不覆盖 primary/ring；状态色（success/warning/idle）走 custom 槽。
  return base.copyWith(
    custom: {
      'success':
          brightness == Brightness.light ? const Color(0xFF16A34A) : const Color(0xFF22C55E),
      'warning':
          brightness == Brightness.light ? const Color(0xFFD97706) : const Color(0xFFF59E0B),
      'idle':
          brightness == Brightness.light ? const Color(0xFF71717A) : const Color(0xFFA1A1AA),
    },
  );
}

/// Light/Dark shadcn 主题（ShadApp 直接消费）。
/// 官方 zinc 底 + 仅两处许可定制：圆角 10（0.625rem 档）、
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
