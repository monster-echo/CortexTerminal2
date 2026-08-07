import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 由 CLAUDE.md 设计 token 构造 Material 3 ThemeData（dark + light）。
/// 组件规范：主按钮 48dp 胶囊 / 输入框 48dp 8dp 圆角 / 卡片 12dp / 间距 4·8·16·24。
ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? AppColors.darkPrimaryButton : AppColors.lightPrimaryButton,
    onPrimary: dark ? AppColors.darkOnPrimaryButton : AppColors.lightOnPrimaryButton,
    secondary: dark ? AppColors.darkSecondary : AppColors.lightSecondary,
    onSecondary: dark ? AppColors.darkSurface : AppColors.lightSurface,
    tertiary: dark ? AppColors.darkTertiary : AppColors.lightTertiary,
    onTertiary: dark ? AppColors.darkPrimary : AppColors.lightPrimary,
    error: dark ? AppColors.darkError : AppColors.lightError,
    onError: Colors.white,
    surface: dark ? AppColors.darkSurface : AppColors.lightSurface,
    onSurface: dark ? AppColors.darkPrimary : AppColors.lightPrimary,
    onSurfaceVariant: dark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
    outline: dark ? AppColors.darkOutline : AppColors.lightOutline,
    outlineVariant: dark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant,
    surfaceContainerLowest: dark ? const Color(0xFF0c1015) : const Color(0xFFfafafa),
    surfaceContainerLow: dark ? const Color(0xFF161b26) : const Color(0xFFf7f7f7),
    surfaceContainer: dark ? AppColors.darkContainer : AppColors.lightContainer,
    surfaceContainerHigh: dark ? AppColors.darkContainerHigh : AppColors.lightContainerHigh,
    surfaceContainerHighest: dark ? AppColors.darkContainerHighest : AppColors.lightContainerHighest,
  );

  final base = ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    useMaterial3: true,
  );

  return base.copyWith(
    // 主操作按钮：48dp 胶囊，禁用 opacity 0.5
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(120, 48),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        disabledForegroundColor: scheme.onPrimary.withValues(alpha: 0.5),
        disabledBackgroundColor: scheme.primary.withValues(alpha: 0.5),
      ),
    ),
    // 次要按钮：透明 + 1dp outline_variant 边框，8dp 圆角
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(96, 48),
        side: BorderSide(color: scheme.outlineVariant, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    // 输入框：48dp，surface_container_high 底，8dp 圆角
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    // 卡片：12dp
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
