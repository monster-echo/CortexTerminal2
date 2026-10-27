import '../../shared/layout/adaptive_page_scaffold.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/theme/corterm_theme.dart';
import '../../core/models/terminal_color_scheme.dart';
import '../../core/storage/app_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/list_group.dart';
import '../../shared/widgets/unsaved_changes_guard.dart';

/// 终端主题编辑器：新建 / 编辑自定义主题（名称 + 20 个 hex 色值）。
/// [initial] 为空 = 新建；传入 = 编辑既有自定义主题。
class TerminalThemeEditorScreen extends ConsumerStatefulWidget {
  const TerminalThemeEditorScreen({super.key, this.initial});

  final TerminalColorScheme? initial;

  @override
  ConsumerState<TerminalThemeEditorScreen> createState() =>
      _TerminalThemeEditorScreenState();
}

class _TerminalThemeEditorScreenState
    extends ConsumerState<TerminalThemeEditorScreen> {
  late final TextEditingController _nameController;
  late final Map<String, TextEditingController> _colorControllers;
  String? _error;
  final _scroll = ScrollController();
  void _showError(String message) {
    setState(() => _error = message);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  bool _saving = false;
  bool _saved = false;
  bool get _dirty =>
      _nameController.text != (widget.initial?.name ?? '') ||
      TerminalColorScheme.colorFields.any(
        (key) =>
            _colorControllers[key]!.text !=
            (widget.initial ?? builtinTerminalColorSchemes.first).field(key),
      );
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _colorControllers = {
      for (final f in TerminalColorScheme.colorFields)
        f: TextEditingController(
          text: (initial ?? builtinTerminalColorSchemes.first).field(f),
        ),
    };
    _nameController.addListener(_changed);
    for (final controller in _colorControllers.values) {
      controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _nameController.dispose();
    for (final c in _colorControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context)!;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError(l10n.terminalThemeNameRequired);
      return;
    }
    // 统一校验：任一色值非法 → 整体不保存，错误显示在页面上。
    final values = <String, String>{};
    for (final entry in _colorControllers.entries) {
      final raw = entry.value.text.trim();
      try {
        TerminalColorScheme.parseHex(raw);
      } on FormatException {
        _showError('${l10n.terminalThemeInvalidColor}: ${entry.key} "$raw"');
        return;
      }
      values[entry.key] = raw;
    }

    final existing = widget.initial;
    // 新建 id 用时间戳；编辑沿用原 id。
    final id =
        existing?.id ?? 'custom-${DateTime.now().millisecondsSinceEpoch}';
    var scheme = TerminalColorScheme(
      id: id,
      name: name,
      isDark: _guessIsDark(values),
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

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(customTerminalThemesProvider.notifier).save(scheme);
      await ref.read(terminalThemeSelectionProvider.notifier).set(id);
      if (mounted) setState(() => _saved = true);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.pop();
        });
      }
    } catch (error) {
      if (mounted) _showError('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 新建时按背景亮度做一次深浅归类。
  bool _guessIsDark(Map<String, String> values) {
    final bg = TerminalColorScheme.parseHex(values['background']!);
    return bg.computeLuminance() < 0.5;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);

    return UnsavedChangesGuard(
      dirty: _dirty && !_saved,
      busy: _saving,
      child: AdaptivePageScaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(l10n.terminalThemeEdit),
          actions: [
            IconButton(
              tooltip: l10n.save,
              icon: const Icon(Icons.check),
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
        body: ListView(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            // 错误信息显式展示（非法 hex / 空名称），不做静默兜底。
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: theme.textTheme.small.copyWith(
                    color: colorsOf(context).danger,
                  ),
                ),
              ),
            _TerminalPreview(controllers: _colorControllers),
            const SizedBox(height: 16),
            AppGroupCard(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: ShadInput(
                    controller: _nameController,
                    placeholder: Text(l10n.terminalThemeNameLabel),
                  ),
                ),
              ],
            ),
            AppGroupCard(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final fieldKey in TerminalColorScheme.colorFields)
                  _ColorFieldRow(
                    fieldKey: fieldKey,
                    controller: _colorControllers[fieldKey]!,
                  ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _TerminalPreview extends StatelessWidget {
  const _TerminalPreview({required this.controllers});
  final Map<String, TextEditingController> controllers;
  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    try {
      final bg = TerminalColorScheme.parseHex(
        controllers['background']!.text.trim(),
      );
      final fg = TerminalColorScheme.parseHex(
        controllers['foreground']!.text.trim(),
      );
      final a = bg.computeLuminance();
      final b = fg.computeLuminance();
      final contrast = ((a > b ? a : b) + 0.05) / ((a < b ? a : b) + 0.05);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: bg,
            child: Text(
              'user@computer ~ % ls\nproject/  README.md\n> _',
              style: TextStyle(color: fg, fontFamily: 'monospace', height: 1.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            zh
                ? '文字对比度 ${contrast.toStringAsFixed(1)}:1${contrast < 4.5 ? ' · 建议至少 4.5:1' : ''}'
                : 'Text contrast ${contrast.toStringAsFixed(1)}:1${contrast < 4.5 ? ' · Aim for at least 4.5:1' : ''}',
          ),
        ],
      );
    } on FormatException {
      return Text(
        zh
            ? '背景或前景色无效，无法预览。'
            : 'Enter valid background and foreground colors to preview.',
      );
    }
  }
}

/// 单个颜色行：色块（实时预览）+ 字段名 + hex 输入。
class _ColorFieldRow extends StatelessWidget {
  const _ColorFieldRow({required this.fieldKey, required this.controller});

  final String fieldKey;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    const labels = {
      'background': '背景',
      'foreground': '文字',
      'cursor': '光标',
      'selection': '选中区',
      'black': '黑色',
      'red': '红色',
      'green': '绿色',
      'yellow': '黄色',
      'blue': '蓝色',
      'magenta': '品红',
      'cyan': '青色',
      'white': '白色',
      'brightBlack': '亮黑',
      'brightRed': '亮红',
      'brightGreen': '亮绿',
      'brightYellow': '亮黄',
      'brightBlue': '亮蓝',
      'brightMagenta': '亮品红',
      'brightCyan': '亮青',
      'brightWhite': '亮白',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              Color? preview;
              try {
                preview = TerminalColorScheme.parseHex(controller.text.trim());
              } on FormatException {
                preview = null;
              }
              return Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: preview,
                  shape: BoxShape.circle,
                  border: Border.all(color: colorsOf(context).divider),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              zh ? labels[fieldKey]! : fieldKey,
              style: theme.textTheme.small,
            ),
          ),
          SizedBox(
            width: 110,
            child: ShadInput(
              controller: controller,
              placeholder: const Text('#RRGGBB'),
            ),
          ),
        ],
      ),
    );
  }
}
