import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 实例，main() 启动时 override 注入。
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Overridden in main() with the real instance'),
);

/// 本地偏好持久化（§60）：主题、语言、最近会话、终端设置。
class AppPreferences {
  AppPreferences(this._prefs);

  final SharedPreferences _prefs;

  static const _kThemeMode = 'ui.theme_mode';
  static const _kLocale = 'ui.locale';
  static const _kLastSessionId = 'workspace.last_session_id';
  static const _kFontSize = 'terminal.font_size';
  static const _kKeepAwake = 'terminal.keep_awake';

  ThemeMode get themeMode => switch (_prefs.getString(_kThemeMode)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString(_kThemeMode, mode.name);

  /// null = 跟随系统；'en' / 'zh'。历史脏数据（''）按未设置处理。
  String? get localeTag {
    final v = _prefs.getString(_kLocale);
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setLocaleTag(String? tag) async {
    if (tag == null || tag.isEmpty) {
      await _prefs.remove(_kLocale);
    } else {
      await _prefs.setString(_kLocale, tag);
    }
  }

  String? get lastSessionId => _prefs.getString(_kLastSessionId);

  Future<void> setLastSessionId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kLastSessionId);
    } else {
      await _prefs.setString(_kLastSessionId, id);
    }
  }

  static const minFontSize = 8.0;
  static const maxFontSize = 24.0;
  static const defaultFontSize = 13.0;

  double get terminalFontSize =>
      (_prefs.getDouble(_kFontSize) ?? defaultFontSize).clamp(minFontSize, maxFontSize);

  Future<void> setTerminalFontSize(double size) =>
      _prefs.setDouble(_kFontSize, size.clamp(minFontSize, maxFontSize));

  /// 会话进行中保持屏幕常亮（§51），默认开。
  bool get keepScreenAwake => _prefs.getBool(_kKeepAwake) ?? true;

  Future<void> setKeepScreenAwake(bool v) => _prefs.setBool(_kKeepAwake, v);
}

class KeepAwakeController extends StateNotifier<bool> {
  KeepAwakeController(this._prefs) : super(_prefs.keepScreenAwake);

  final AppPreferences _prefs;

  Future<void> set(bool v) async {
    await _prefs.setKeepScreenAwake(v);
    state = v;
  }
}

final keepAwakeProvider = StateNotifierProvider<KeepAwakeController, bool>(
  (ref) => KeepAwakeController(ref.watch(appPreferencesProvider)),
);

/// 终端字号（响应式：Settings 修改即时生效到 TerminalView）。
class FontSizeController extends StateNotifier<double> {
  FontSizeController(this._prefs) : super(_prefs.terminalFontSize);

  final AppPreferences _prefs;

  Future<void> set(double size) async {
    await _prefs.setTerminalFontSize(size);
    state = size;
  }
}

final fontSizeProvider = StateNotifierProvider<FontSizeController, double>(
  (ref) => FontSizeController(ref.watch(appPreferencesProvider)),
);

/// 外观模式（§52）：System / Light / Dark，默认 System。
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._prefs) : super(_prefs.themeMode);

  final AppPreferences _prefs;

  Future<void> set(ThemeMode mode) async {
    await _prefs.setThemeMode(mode);
    state = mode;
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(ref.watch(appPreferencesProvider)),
);

/// 语言（§72）：null = 跟随系统，'en' / 'zh'。
class LocaleController extends StateNotifier<String?> {
  LocaleController(this._prefs) : super(_prefs.localeTag);

  final AppPreferences _prefs;

  Future<void> set(String? tag) async {
    await _prefs.setLocaleTag(tag);
    state = tag;
  }
}

final localeProvider = StateNotifierProvider<LocaleController, String?>(
  (ref) => LocaleController(ref.watch(appPreferencesProvider)),
);

final appPreferencesProvider = Provider<AppPreferences>(
  (ref) => AppPreferences(ref.watch(sharedPreferencesProvider)),
);
