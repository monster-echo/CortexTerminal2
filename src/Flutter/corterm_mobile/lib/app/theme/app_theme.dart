/// 设计 token（§35/36）+ shadcn 主题构建。
///
/// 唯一允许出现 hex 的地方（shadcn/ui 同规则）：色板集中在 [AppColors]，
/// 组件一律从 `ShadTheme.of(context)` 取色。
library;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 色板（Light §35 / Dark §36，共享强调色）。
class AppColors {
  // Light（§35）
  static const lightBackground = Color(0xFFFAFAFA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightTextPrimary = Color(0xFF111111);
  static const lightTextSecondary = Color(0xFF737373);
  static const lightBorder = Color(0xFFE5E5E5);
  // Dark（§36）
  static const darkBackground = Color(0xFF090909);
  static const darkSurface = Color(0xFF111111);
  static const darkSurfaceSecondary = Color(0xFF171717);
  static const darkTextPrimary = Color(0xFFF5F5F5);
  static const darkTextSecondary = Color(0xFFA3A3A3);
  static const darkBorder = Color(0xFF262626);
  // 共享
  static const accent = Color(0xFF2563EB);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);

  /// Session 状态点（§13）：绿=运行，黄=等待/重连，红=错误，灰=断开/结束。
  static const statusRunning = success;
  static const statusWaiting = warning;
  static const statusError = danger;
  static const statusEnded = darkTextSecondary;
}

ShadColorScheme _lightScheme() => const ShadColorScheme(
      background: AppColors.lightBackground,
      foreground: AppColors.lightTextPrimary,
      card: AppColors.lightSurface,
      cardForeground: AppColors.lightTextPrimary,
      popover: AppColors.lightSurface,
      popoverForeground: AppColors.lightTextPrimary,
      primary: AppColors.accent,
      primaryForeground: Colors.white,
      secondary: AppColors.lightSurface,
      secondaryForeground: AppColors.lightTextPrimary,
      muted: Color(0xFFF0F0F0),
      mutedForeground: AppColors.lightTextSecondary,
      accent: Color(0xFFF0F0F0),
      accentForeground: AppColors.lightTextPrimary,
      destructive: AppColors.danger,
      destructiveForeground: Colors.white,
      border: AppColors.lightBorder,
      input: AppColors.lightBorder,
      ring: AppColors.accent,
      selection: Color(0x402563EB),
    );

ShadColorScheme _darkScheme() => const ShadColorScheme(
      background: AppColors.darkBackground,
      foreground: AppColors.darkTextPrimary,
      card: AppColors.darkSurface,
      cardForeground: AppColors.darkTextPrimary,
      popover: AppColors.darkSurface,
      popoverForeground: AppColors.darkTextPrimary,
      primary: AppColors.accent,
      primaryForeground: Colors.white,
      secondary: AppColors.darkSurfaceSecondary,
      secondaryForeground: AppColors.darkTextPrimary,
      muted: AppColors.darkSurfaceSecondary,
      mutedForeground: AppColors.darkTextSecondary,
      accent: AppColors.darkSurfaceSecondary,
      accentForeground: AppColors.darkTextPrimary,
      destructive: AppColors.danger,
      destructiveForeground: Colors.white,
      border: AppColors.darkBorder,
      input: AppColors.darkBorder,
      ring: AppColors.accent,
      selection: Color(0x402563EB),
    );

/// Light/Dark shadcn 主题（ShadApp 直接消费）。
ShadThemeData shadLightTheme() => ShadThemeData(
      brightness: Brightness.light,
      colorScheme: _lightScheme(),
    );

ShadThemeData shadDarkTheme() => ShadThemeData(
      brightness: Brightness.dark,
      colorScheme: _darkScheme(),
    );
