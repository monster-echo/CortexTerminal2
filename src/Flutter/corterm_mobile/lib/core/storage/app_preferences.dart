import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/terminal_color_scheme.dart';

/// SharedPreferences 实例，main() 启动时 override 注入。
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Overridden in main() with the real instance'),
);

/// 终端 scrollback 快照存储（按 workerId 键）。
/// SessionController 只依赖此接口，测试可给内存实现。
abstract interface class TerminalSnapshotStore {
  String? terminalSnapshot(String key);
  Future<void> setTerminalSnapshot(String key, String text);

  /// 输出流缓存（TerminalCache 对等：按 session 缓存原始输出流，
  /// 打开会话时先绘制缓存画面，随后由服务端全量重放权威覆盖）。
  String? terminalStreamCache(String key);
  Future<void> setTerminalStreamCache(String key, String text);

  /// 输出游标（TerminalCache.loadLastSeq 对等：增量重放起点）。
  int terminalSeq(String key);
  Future<void> setTerminalSeq(String key, int seq);
}

/// 本地偏好持久化（§60）：主题、语言、最近会话、终端设置。
class AppPreferences implements TerminalSnapshotStore {
  AppPreferences(this._prefs);

  final SharedPreferences _prefs;

  static const _kThemeMode = 'ui.theme_mode';
  static const _kTerminalThemeMode = 'terminal.theme_mode';
  static const _kTerminalThemeSelection = 'terminal.theme_selection';
  static const _kTerminalCustomThemes = 'terminal.custom_themes';
  static const _kLocale = 'ui.locale';
  static const _kLastSessionId = 'workspace.last_session_id';
  static const _kFontSize = 'terminal.font_size';
  static const _kKeepAwake = 'terminal.keep_awake';
  static const _kDismissedAnnouncements = 'announcements.dismissed';
  static const _kSnapshotPrefix = 'terminal.snapshot.';

  /// 终端 scrollback 快照（App 冷启动后恢复上次输出；
  /// 对齐 ArkTS TerminalCache 的按 Worker 持久化）。
  @override
  String? terminalSnapshot(String key) =>
      _prefs.getString(_kSnapshotPrefix + key);

  @override
  Future<void> setTerminalSnapshot(String key, String text) =>
      _prefs.setString(_kSnapshotPrefix + key, text);

  static const _kStreamPrefix = 'terminal.stream.';
  static const _kSeqPrefix = 'terminal.seq.';

  @override
  String? terminalStreamCache(String key) =>
      _prefs.getString(_kStreamPrefix + key);

  @override
  Future<void> setTerminalStreamCache(String key, String text) =>
      _prefs.setString(_kStreamPrefix + key, text);

  @override
  int terminalSeq(String key) => _prefs.getInt(_kSeqPrefix + key) ?? 0;

  @override
  Future<void> setTerminalSeq(String key, int seq) =>
      _prefs.setInt(_kSeqPrefix + key, seq);

  /// 已关闭的公告 id（对齐 ArkTS AnnouncementService 的按设备已读记录）。
  List<String> get dismissedAnnouncementIds =>
      _prefs.getStringList(_kDismissedAnnouncements) ?? const [];

  Future<void> dismissAnnouncement(String id) async {
    final dismissed = [...dismissedAnnouncementIds];
    if (!dismissed.contains(id)) {
      dismissed.add(id);
      await _prefs.setStringList(_kDismissedAnnouncements, dismissed);
    }
  }

  ThemeMode get themeMode => switch (_prefs.getString(_kThemeMode)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString(_kThemeMode, mode.name);

  /// 终端配色模式（§52 扩展）：'system'（跟随 App）/ 'dark' / 'light'，默认 system。
  String get terminalThemeMode =>
      switch (_prefs.getString(_kTerminalThemeMode)) {
        'dark' => 'dark',
        'light' => 'light',
        _ => 'system',
      };

  Future<void> setTerminalThemeMode(String mode) =>
      _prefs.setString(_kTerminalThemeMode, mode);

  /// 终端主题选择：'followApp'（跟随 App 深浅）或主题档案 id（内置/自定义）。
  /// 迁移：旧 terminalThemeMode('system'/'dark'/'light') 映射到新语义。
  String get terminalThemeSelection {
    final v = _prefs.getString(_kTerminalThemeSelection);
    if (v != null && v.isNotEmpty) return v;
    return switch (_prefs.getString(_kTerminalThemeMode)) {
      'dark' => 'default-dark',
      'light' => 'default-light',
      _ => followAppTerminalTheme,
    };
  }

  Future<void> setTerminalThemeSelection(String selection) =>
      _prefs.setString(_kTerminalThemeSelection, selection);

  /// 自定义终端主题（JSON 列表）。解析交给上层（provider），非法条目直接抛错。
  List<String> get customTerminalThemeJsons =>
      _prefs.getStringList(_kTerminalCustomThemes) ?? const [];

  Future<void> setCustomTerminalThemeJsons(List<String> jsons) =>
      _prefs.setStringList(_kTerminalCustomThemes, jsons);

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

/// 终端主题选择：'followApp' 或主题档案 id。
class TerminalThemeSelectionController extends StateNotifier<String> {
  TerminalThemeSelectionController(this._prefs)
      : super(_prefs.terminalThemeSelection);

  final AppPreferences _prefs;

  Future<void> set(String selection) async {
    await _prefs.setTerminalThemeSelection(selection);
    state = selection;
  }
}

final terminalThemeSelectionProvider =
    StateNotifierProvider<TerminalThemeSelectionController, String>(
  (ref) =>
      TerminalThemeSelectionController(ref.watch(appPreferencesProvider)),
);

/// 自定义终端主题列表（已反序列化；非法 JSON 直接抛错暴露问题）。
final customTerminalThemesProvider =
    StateNotifierProvider<CustomTerminalThemesController, List<TerminalColorScheme>>(
  (ref) => CustomTerminalThemesController(ref.watch(appPreferencesProvider)),
);

class CustomTerminalThemesController
    extends StateNotifier<List<TerminalColorScheme>> {
  CustomTerminalThemesController(this._prefs)
      : super([
          for (final json in _prefs.customTerminalThemeJsons)
            TerminalColorScheme.fromJson(
              jsonDecode(json) as Map<String, Object>,
            ),
        ]);

  final AppPreferences _prefs;

  Future<void> _persist() => _prefs.setCustomTerminalThemeJsons([
        for (final s in state) jsonEncode(s.toJson()),
      ]);

  /// 新增或按 id 覆盖保存，并使其生效（返回 id）。
  Future<String> save(TerminalColorScheme scheme) async {
    final next = [
      for (final s in state)
        if (s.id != scheme.id) s,
      scheme,
    ];
    state = next;
    await _persist();
    return scheme.id;
  }

  Future<void> delete(String id) async {
    state = [
      for (final s in state)
        if (s.id != id) s,
    ];
    await _persist();
  }
}

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
