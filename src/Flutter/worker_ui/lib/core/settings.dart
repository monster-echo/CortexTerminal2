import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置（主题 / 语言），持久化到 shared_preferences。
/// worker 二进制路径由 App 自动管理（打包 + 自动装到 ~/.corterm），不提供手动覆盖。
class Settings extends ChangeNotifier {
  static final Settings instance = Settings._();

  Settings._();

  static const _kThemeMode = 'themeMode';
  static const _kLocale = 'locale';

  ThemeMode _themeMode = ThemeMode.system;
  String _locale = 'zh';

  ThemeMode get themeMode => _themeMode;
  String get locale => _locale;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == prefs.getString(_kThemeMode),
      orElse: () => ThemeMode.system,
    );
    _locale = prefs.getString(_kLocale) ?? 'zh';
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode.name);
    notifyListeners();
  }

  Future<void> setLocale(String locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocale, locale);
    notifyListeners();
  }
}
