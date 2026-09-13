import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_colors.dart';

/// 由 CLAUDE.md 设计 token 构造 shadcn 主题（dark + light）。
/// 与 corterm_mobile 同规则：hex 只允许出现在 [AppColors]，组件一律
/// 从 `ShadTheme.of(context).colorScheme` 取色。
///
/// tertiary（成功/在线绿）与 link（次要文字/链接）shadcn 色板没有对应槽位，
/// 放 `custom` map，经下方 extension 取用。
ShadColorScheme _lightScheme() => const ShadColorScheme(
      background: AppColors.lightSurface,
      foreground: AppColors.lightPrimary,
      card: AppColors.lightContainer,
      cardForeground: AppColors.lightPrimary,
      popover: AppColors.lightContainerHighest,
      popoverForeground: AppColors.lightPrimary,
      primary: AppColors.lightPrimaryButton,
      primaryForeground: AppColors.lightOnPrimaryButton,
      secondary: AppColors.lightContainerHigh,
      secondaryForeground: AppColors.lightPrimary,
      muted: AppColors.lightContainerHigh,
      mutedForeground: AppColors.lightOnSurfaceVariant,
      accent: AppColors.lightContainerHighest,
      accentForeground: AppColors.lightPrimary,
      destructive: AppColors.lightError,
      destructiveForeground: AppColors.lightOnPrimaryButton,
      border: AppColors.lightOutlineVariant,
      input: AppColors.lightOutlineVariant,
      ring: AppColors.lightSecondary,
      selection: Color(0x401a8cd8),
      custom: {'link': AppColors.lightSecondary, 'tertiary': AppColors.lightTertiary},
    );

ShadColorScheme _darkScheme() => const ShadColorScheme(
      background: AppColors.darkSurface,
      foreground: AppColors.darkPrimary,
      card: AppColors.darkContainer,
      cardForeground: AppColors.darkPrimary,
      popover: AppColors.darkContainerHighest,
      popoverForeground: AppColors.darkPrimary,
      primary: AppColors.darkPrimaryButton,
      primaryForeground: AppColors.darkOnPrimaryButton,
      secondary: AppColors.darkContainer,
      secondaryForeground: AppColors.darkPrimary,
      muted: AppColors.darkContainer,
      mutedForeground: AppColors.darkOnSurfaceVariant,
      accent: AppColors.darkContainerHigh,
      accentForeground: AppColors.darkPrimary,
      destructive: AppColors.darkError,
      destructiveForeground: AppColors.darkOnPrimaryButton,
      border: AppColors.darkOutlineVariant,
      input: AppColors.darkOutlineVariant,
      ring: AppColors.darkSecondary,
      selection: Color(0x407cacf8),
      custom: {'link': AppColors.darkSecondary, 'tertiary': AppColors.darkTertiary},
    );

/// [ShadColorScheme.custom] 的类型安全取用：链接/次要文字色与成功/在线色。
extension WorkerSchemeX on ShadColorScheme {
  Color get link => custom['link']!;
  Color get tertiary => custom['tertiary']!;
}

/// Light/Dark shadcn 主题（ShadApp 直接消费）。
/// 组件规范：全局圆角 8dp（输入框/小按钮），卡片 12dp，主/次按钮 48dp 高。
ShadThemeData shadLightTheme() => _theme(Brightness.light, _lightScheme());

ShadThemeData shadDarkTheme() => _theme(Brightness.dark, _darkScheme());

ShadThemeData _theme(Brightness brightness, ShadColorScheme scheme) => ShadThemeData(
      brightness: brightness,
      colorScheme: scheme,
      radius: BorderRadius.circular(8),
      cardTheme: ShadCardTheme(radius: BorderRadius.circular(12)),
      primaryButtonTheme: const ShadButtonTheme(height: 48),
      outlineButtonTheme: const ShadButtonTheme(height: 48),
    );
