import 'package:flutter/material.dart';

/// CLAUDE.md 设计 token（深色 + 浅色），与 Harmony/MAUI 客户端共用同一套色板。
/// https://developer.huawei.com/consumer/cn/forum/topic/0204198799066197038
/// 按钮蓝 #1a8cd8（白字 3.63:1 ≥ 按钮 3:1）；浅色次要文字 #0a6fc2（4.74:1 ≥ 正文 4.5:1）。
class AppColors {
  AppColors._();

  // ── Dark ──
  static const Color darkSurface = Color(0xFF0f1419);
  static const Color darkContainer = Color(0xFF1a1f2e);
  static const Color darkContainerHigh = Color(0xFF232a3b);
  static const Color darkContainerHighest = Color(0xFF2d3548);
  static const Color darkPrimary = Color(0xFFe7e9ea);
  static const Color darkSecondary = Color(0xFF7cacf8);
  static const Color darkPrimaryButton = Color(0xFF1a8cd8);
  static const Color darkOnPrimaryButton = Color(0xFFffffff);
  static const Color darkTertiary = Color(0xFF00ba7c);
  static const Color darkError = Color(0xFFff5c5c);
  static const Color darkOnSurfaceVariant = Color(0xFF9aa4b0);
  static const Color darkOutline = Color(0xFF6b7785);
  static const Color darkOutlineVariant = Color(0xFF2f3336);

  // ── Light ──
  static const Color lightSurface = Color(0xFFf5f5f5);
  static const Color lightContainer = Color(0xFFffffff);
  static const Color lightContainerHigh = Color(0xFFf0f0f0);
  static const Color lightContainerHighest = Color(0xFFe8e8e8);
  static const Color lightPrimary = Color(0xFF1a1a1a);
  static const Color lightSecondary = Color(0xFF0a6fc2);
  static const Color lightPrimaryButton = Color(0xFF1a8cd8);
  static const Color lightOnPrimaryButton = Color(0xFFffffff);
  static const Color lightTertiary = Color(0xFF00824f);
  static const Color lightError = Color(0xFFc81823);
  static const Color lightOnSurfaceVariant = Color(0xFF536471);
  static const Color lightOutline = Color(0xFF7a8590);
  static const Color lightOutlineVariant = Color(0xFFe0e0e0);
}
