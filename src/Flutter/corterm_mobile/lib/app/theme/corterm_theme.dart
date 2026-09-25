import 'package:flutter/material.dart';

/// Corterm 设计系统 token（design/07-design-system.md）。
///
/// 两个上下文：
/// - Light App Context：首页 / 侧边栏 / 搜索 / 电脑 / 工作区 / 新建流程。
/// - Dark Tool Context：Session xterm / 文件 / 端口转发。
class CortermColors extends ThemeExtension<CortermColors> {
  const CortermColors({
    required this.background,
    required this.surface,
    required this.surfaceSelected,
    required this.surfaceElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.onEmphasis,
    required this.emphasis,
    required this.scrim,
    required this.onScrim,
  });

  final Color background;
  final Color surface;
  final Color surfaceSelected;
  final Color surfaceElevated;
  final Color textPrimary;
  final Color textSecondary;
  final Color divider;
  final Color accent;
  final Color success;
  final Color warning;
  final Color danger;

  /// 强调底（accent / 主按钮 / 彩色 hero）上的前景。
  final Color onEmphasis;

  /// 主按钮等“强调底”色：Light=黑底，Dark=白底（ChatGPT 风格）。
  final Color emphasis;

  /// 相机取景/遮罩类全屏黑底。
  final Color scrim;

  /// 遮罩上的前景。
  final Color onScrim;

  static const light = CortermColors(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF5F5F5),
    surfaceSelected: Color(0xFFECECEC),
    surfaceElevated: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF111111),
    textSecondary: Color(0xFF6F6F6F),
    divider: Color(0xFFE7E7E7),
    accent: Color(0xFF4A90F8),
    success: Color(0xFF34C759),
    warning: Color(0xFFFF9F0A),
    danger: Color(0xFFFF3B30),
    onEmphasis: Color(0xFFFFFFFF),
    emphasis: Color(0xFF111111),
    scrim: Color(0xFF000000),
    onScrim: Color(0xFFFFFFFF),
  );

  /// Light App Context 的深色变体（用户切换 Dark 时全局使用）。
  static const dark = CortermColors(
    background: Color(0xFF0B0D0F),
    surface: Color(0xFF171A1F),
    surfaceSelected: Color(0xFF20242A),
    surfaceElevated: Color(0xFF20242A),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xFF9CA3AF),
    divider: Color(0xFF2B3037),
    accent: Color(0xFF3B82F6),
    success: Color(0xFF34C759),
    warning: Color(0xFFFF9F0A),
    danger: Color(0xFFFF453A),
    onEmphasis: Color(0xFF111111),
    emphasis: Color(0xFFF5F5F5),
    scrim: Color(0xFF000000),
    onScrim: Color(0xFFFFFFFF),
  );

  static const darkTool = CortermColors(
    background: Color(0xFF0B0D0F),
    surface: Color(0xFF171A1F),
    surfaceSelected: Color(0xFF20242A),
    surfaceElevated: Color(0xFF20242A),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xFF9CA3AF),
    divider: Color(0xFF2B3037),
    accent: Color(0xFF3B82F6),
    success: Color(0xFF34C759),
    warning: Color(0xFFFF9F0A),
    danger: Color(0xFFFF453A),
    onEmphasis: Color(0xFF111111),
    emphasis: Color(0xFFF5F5F5),
    scrim: Color(0xFF000000),
    onScrim: Color(0xFFFFFFFF),
  );

  @override
  CortermColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceSelected,
    Color? surfaceElevated,
    Color? textPrimary,
    Color? textSecondary,
    Color? divider,
    Color? accent,
    Color? success,
    Color? warning,
    Color? danger,
    Color? onEmphasis,
    Color? emphasis,
    Color? scrim,
    Color? onScrim,
  }) {
    return CortermColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceSelected: surfaceSelected ?? this.surfaceSelected,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      divider: divider ?? this.divider,
      accent: accent ?? this.accent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      onEmphasis: onEmphasis ?? this.onEmphasis,
      emphasis: emphasis ?? this.emphasis,
      scrim: scrim ?? this.scrim,
      onScrim: onScrim ?? this.onScrim,
    );
  }

  @override
  CortermColors lerp(CortermColors? other, double t) {
    if (other == null) return this;
    return CortermColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSelected: Color.lerp(surfaceSelected, other.surfaceSelected, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onEmphasis: Color.lerp(onEmphasis, other.onEmphasis, t)!,
      emphasis: Color.lerp(emphasis, other.emphasis, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      onScrim: Color.lerp(onScrim, other.onScrim, t)!,
    );
  }
}

/// `Theme.of(context).extension<CortermColors>()!` 的快捷方式。
CortermColors colorsOf(BuildContext context) =>
    Theme.of(context).extension<CortermColors>()!;

/// Light App Context 全局主题（design/07 §2）。
ThemeData cortermLightTheme() {
  const c = CortermColors.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: c.background,
    colorScheme: ColorScheme.light(
      primary: c.accent,
      onPrimary: Colors.white,
      secondary: c.accent,
      surface: c.background,
      error: c.danger,
    ),
  );
  return base.copyWith(
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: c.textPrimary,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
    ),
    dividerTheme: DividerThemeData(color: c.divider, thickness: 0.5),
    splashFactory: InkSparkle.splashFactory,
  );
}

/// Dark Tool Context 主题，Session / 文件 / 端口转发页通过 `Theme` 包裹使用。
ThemeData cortermDarkToolTheme() {
  const c = CortermColors.darkTool;
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: c.background,
    colorScheme: ColorScheme.dark(
      primary: c.accent,
      onPrimary: Colors.white,
      secondary: c.accent,
      surface: c.background,
      error: c.danger,
    ),
  );
  return base.copyWith(
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: c.textPrimary,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
    ),
    dividerTheme: DividerThemeData(color: c.divider, thickness: 0.5),
  );
}
