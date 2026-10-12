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
    background: Color(0xFFF8FAFC),
    surface: Color(0xFFEEF2F6),
    surfaceSelected: Color(0xFFEEF2F6),
    surfaceElevated: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF64748B),
    divider: Color(0xFFE5E7EB),
    accent: Color(0xFF0369A1),
    success: Color(0xFF15803D),
    warning: Color(0xFFA16207),
    danger: Color(0xFFB91C1C),
    onEmphasis: Color(0xFFF8FAFC),
    emphasis: Color(0xFF111827),
    scrim: Color(0xFF000000),
    onScrim: Color(0xFFFFFFFF),
  );

  /// Light App Context 的深色变体（用户切换 Dark 时全局使用）。
  static const dark = CortermColors(
    background: Color(0xFF0F1419),
    surface: Color(0xFF1F2937),
    surfaceSelected: Color(0xFF232B36),
    surfaceElevated: Color(0xFF161B22),
    textPrimary: Color(0xFFE5E7EB),
    textSecondary: Color(0xFF94A3B8),
    divider: Color(0xFF26313D),
    accent: Color(0xFF7DD3FC),
    success: Color(0xFF86EFAC),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFFCA5A5),
    onEmphasis: Color(0xFF111827),
    emphasis: Color(0xFFF8FAFC),
    scrim: Color(0xFF000000),
    onScrim: Color(0xFFFFFFFF),
  );

  static const darkTool = CortermColors(
    background: Color(0xFF0F1419),
    surface: Color(0xFF1F2937),
    surfaceSelected: Color(0xFF232B36),
    surfaceElevated: Color(0xFF161B22),
    textPrimary: Color(0xFFE5E7EB),
    textSecondary: Color(0xFF94A3B8),
    divider: Color(0xFF26313D),
    accent: Color(0xFF7DD3FC),
    success: Color(0xFF86EFAC),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFFCA5A5),
    onEmphasis: Color(0xFF111827),
    emphasis: Color(0xFFF8FAFC),
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

/// Short, quiet navigation motion shared by ArkTS-parity pages.
class CortermPageTransitionsBuilder extends PageTransitionsBuilder {
  const CortermPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final direction = Directionality.of(context) == TextDirection.rtl
        ? -1.0
        : 1.0;
    final offset = Tween<Offset>(
      begin: Offset(0.08 * direction, 0),
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: SlideTransition(position: animation.drive(offset), child: child),
    );
  }
}

const cortermPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: CortermPageTransitionsBuilder(),
    TargetPlatform.iOS: CortermPageTransitionsBuilder(),
    TargetPlatform.linux: CortermPageTransitionsBuilder(),
    TargetPlatform.macOS: CortermPageTransitionsBuilder(),
    TargetPlatform.windows: CortermPageTransitionsBuilder(),
    TargetPlatform.fuchsia: CortermPageTransitionsBuilder(),
  },
);

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
    pageTransitionsTheme: cortermPageTransitions,
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

/// Tool pages use the same app theme as the rest of the navigation stack.
/// Terminal colors are scoped to the terminal screen only.
ThemeData cortermToolTheme(BuildContext context) => Theme.of(context);

/// Base material theme used only to derive per-session terminal colors.
ThemeData cortermDarkTerminalTheme() {
  const c = CortermColors.darkTool;
  return ThemeData(
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
    extensions: [c],
    pageTransitionsTheme: cortermPageTransitions,
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: c.textPrimary,
    ),
    dividerTheme: DividerThemeData(color: c.divider, thickness: 0.5),
  );
}
