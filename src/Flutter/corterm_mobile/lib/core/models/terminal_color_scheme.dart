import 'dart:ui';

/// 终端主题档案：Flutter / ArkTS / webview 三端共用的统一 20 色模型。
/// 内置预设只读；自定义主题以 JSON 存于本地偏好。
class TerminalColorScheme {
  const TerminalColorScheme({
    required this.id,
    required this.name,
    required this.isDark,
    required this.background,
    required this.foreground,
    required this.cursor,
    required this.selection,
    required this.black,
    required this.red,
    required this.green,
    required this.yellow,
    required this.blue,
    required this.magenta,
    required this.cyan,
    required this.white,
    required this.brightBlack,
    required this.brightRed,
    required this.brightGreen,
    required this.brightYellow,
    required this.brightBlue,
    required this.brightMagenta,
    required this.brightCyan,
    required this.brightWhite,
  });

  final String id;
  final String name;

  /// 深浅归类：'followApp' 解析与系统状态栏依赖它。
  final bool isDark;
  final String background;
  final String foreground;
  final String cursor;
  final String selection;
  final String black;
  final String red;
  final String green;
  final String yellow;
  final String blue;
  final String magenta;
  final String cyan;
  final String white;
  final String brightBlack;
  final String brightRed;
  final String brightGreen;
  final String brightYellow;
  final String brightBlue;
  final String brightMagenta;
  final String brightCyan;
  final String brightWhite;

  /// 编辑器固定遍历顺序（不含 id/name/isDark）。
  static const colorFields = [
    'background',
    'foreground',
    'cursor',
    'selection',
    'black',
    'red',
    'green',
    'yellow',
    'blue',
    'magenta',
    'cyan',
    'white',
    'brightBlack',
    'brightRed',
    'brightGreen',
    'brightYellow',
    'brightBlue',
    'brightMagenta',
    'brightCyan',
    'brightWhite',
  ];

  String field(String name) => switch (name) {
        'background' => background,
        'foreground' => foreground,
        'cursor' => cursor,
        'selection' => selection,
        'black' => black,
        'red' => red,
        'green' => green,
        'yellow' => yellow,
        'blue' => blue,
        'magenta' => magenta,
        'cyan' => cyan,
        'white' => white,
        'brightBlack' => brightBlack,
        'brightRed' => brightRed,
        'brightGreen' => brightGreen,
        'brightYellow' => brightYellow,
        'brightBlue' => brightBlue,
        'brightMagenta' => brightMagenta,
        'brightCyan' => brightCyan,
        'brightWhite' => brightWhite,
        _ => throw ArgumentError('Unknown color field: $name'),
      };

  TerminalColorScheme copyWithField(String fieldKey, String hex) {
    assert(colorFields.contains(fieldKey));
    final values = {for (final f in colorFields) f: field(f)};
    values[fieldKey] = hex;
    return TerminalColorScheme(
      id: id,
      name: name,
      isDark: isDark,
      background: values['background']!,
      foreground: values['foreground']!,
      cursor: values['cursor']!,
      selection: values['selection']!,
      black: values['black']!,
      red: values['red']!,
      green: values['green']!,
      yellow: values['yellow']!,
      blue: values['blue']!,
      magenta: values['magenta']!,
      cyan: values['cyan']!,
      white: values['white']!,
      brightBlack: values['brightBlack']!,
      brightRed: values['brightRed']!,
      brightGreen: values['brightGreen']!,
      brightYellow: values['brightYellow']!,
      brightBlue: values['brightBlue']!,
      brightMagenta: values['brightMagenta']!,
      brightCyan: values['brightCyan']!,
      brightWhite: values['brightWhite']!,
    );
  }

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'isDark': isDark,
        for (final f in colorFields) f: field(f),
      };

  /// JSON 反序列化：字段缺失或格式非法直接抛错，由调用方展示，不做静默兜底。
  factory TerminalColorScheme.fromJson(Map<String, Object> json) {
    Object require(String key) {
      final v = json[key];
      if (v is! String || v.isEmpty) {
        throw FormatException('TerminalColorScheme: missing field "$key"');
      }
      return v;
    }

    final values = {for (final f in colorFields) f: require(f) as String};
    return TerminalColorScheme(
      id: require('id') as String,
      name: require('name') as String,
      isDark: json['isDark'] == true,
      background: values['background']!,
      foreground: values['foreground']!,
      cursor: values['cursor']!,
      selection: values['selection']!,
      black: values['black']!,
      red: values['red']!,
      green: values['green']!,
      yellow: values['yellow']!,
      blue: values['blue']!,
      magenta: values['magenta']!,
      cyan: values['cyan']!,
      white: values['white']!,
      brightBlack: values['brightBlack']!,
      brightRed: values['brightRed']!,
      brightGreen: values['brightGreen']!,
      brightYellow: values['brightYellow']!,
      brightBlue: values['brightBlue']!,
      brightMagenta: values['brightMagenta']!,
      brightCyan: values['brightCyan']!,
      brightWhite: values['brightWhite']!,
    );
  }

  Color get backgroundColor => parseHex(background);
  Color get foregroundColor => parseHex(foreground);

  /// '#RRGGBB' → Color。非法长度直接抛 FormatException。
  static Color parseHex(String hex) {
    final normalized = hex.replaceFirst('#', '');
    if (normalized.length != 6) {
      throw FormatException('Invalid hex color: $hex');
    }
    return Color(0xFF000000 | int.parse(normalized, radix: 16));
  }
}

const _defaultDark = TerminalColorScheme(
  id: 'default-dark',
  name: 'Default Dark',
  isDark: true,
  background: '#090909',
  foreground: '#F5F5F5',
  cursor: '#3B82F6',
  selection: '#2563EB',
  black: '#090909',
  red: '#EF4444',
  green: '#22C55E',
  yellow: '#F59E0B',
  blue: '#3B82F6',
  magenta: '#D946EF',
  cyan: '#06B6D4',
  white: '#F5F5F5',
  brightBlack: '#737373',
  brightRed: '#F87171',
  brightGreen: '#4ADE80',
  brightYellow: '#FBBF24',
  brightBlue: '#60A5FA',
  brightMagenta: '#E879F9',
  brightCyan: '#22D3EE',
  brightWhite: '#FFFFFF',
);

const _defaultLight = TerminalColorScheme(
  id: 'default-light',
  name: 'Default Light',
  isDark: false,
  background: '#FAFAFA',
  foreground: '#383A42',
  cursor: '#0184BC',
  selection: '#BFCEFF',
  black: '#383A42',
  red: '#D92D3A',
  green: '#0F9F6E',
  yellow: '#C87800',
  blue: '#0184BC',
  magenta: '#A626A4',
  cyan: '#0997B3',
  white: '#FAFAFA',
  brightBlack: '#4F525D',
  brightRed: '#E06C75',
  brightGreen: '#0F9F6E',
  brightYellow: '#B07800',
  brightBlue: '#1689E6',
  brightMagenta: '#C678DD',
  brightCyan: '#56B6C2',
  brightWhite: '#FFFFFF',
);

const _solarizedDark = TerminalColorScheme(
  id: 'solarized-dark',
  name: 'Solarized Dark',
  isDark: true,
  background: '#002B36',
  foreground: '#93A1A1',
  cursor: '#93A1A1',
  selection: '#274642',
  black: '#073642',
  red: '#DC322F',
  green: '#859900',
  yellow: '#B58900',
  blue: '#268BD2',
  magenta: '#D33682',
  cyan: '#2AA198',
  white: '#EEE8D5',
  brightBlack: '#002B36',
  brightRed: '#CB4B16',
  brightGreen: '#586E75',
  brightYellow: '#657B83',
  brightBlue: '#839496',
  brightMagenta: '#6C71C4',
  brightCyan: '#93A1A1',
  brightWhite: '#FDF6E3',
);

const _solarizedLight = TerminalColorScheme(
  id: 'solarized-light',
  name: 'Solarized Light',
  isDark: false,
  background: '#FDF6E3',
  foreground: '#657B83',
  cursor: '#586E75',
  selection: '#EEE8D5',
  black: '#073642',
  red: '#DC322F',
  green: '#859900',
  yellow: '#B58900',
  blue: '#268BD2',
  magenta: '#D33682',
  cyan: '#2AA198',
  white: '#EEE8D5',
  brightBlack: '#839496',
  brightRed: '#CB4B16',
  brightGreen: '#586E75',
  brightYellow: '#657B83',
  brightBlue: '#839496',
  brightMagenta: '#6C71C4',
  brightCyan: '#93A1A1',
  brightWhite: '#FDF6E3',
);

const _nord = TerminalColorScheme(
  id: 'nord',
  name: 'Nord',
  isDark: true,
  background: '#2E3440',
  foreground: '#D8DEE9',
  cursor: '#D8DEE9',
  selection: '#434C5E',
  black: '#3B4252',
  red: '#BF616A',
  green: '#A3BE8C',
  yellow: '#EBCB8B',
  blue: '#81A1C1',
  magenta: '#B48EAD',
  cyan: '#88C0D0',
  white: '#E5E9F0',
  brightBlack: '#4C566A',
  brightRed: '#BF616A',
  brightGreen: '#A3BE8C',
  brightYellow: '#EBCB8B',
  brightBlue: '#81A1C1',
  brightMagenta: '#B48EAD',
  brightCyan: '#8FBCBB',
  brightWhite: '#ECEFF4',
);

/// 内置预设（只读，不可编辑删除）。
const builtinTerminalColorSchemes = [
  _defaultDark,
  _defaultLight,
  _solarizedDark,
  _solarizedLight,
  _nord,
];

/// selection === followAppTerminalTheme 时按 App 深浅模式落到默认深/浅预设。
const followAppTerminalTheme = 'followApp';
