import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/models/terminal_color_scheme.dart';
import '../../core/storage/app_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/list_group.dart';

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

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _colorControllers = {
      for (final f in TerminalColorScheme.colorFields)
        f: TextEditingController(text: initial?.field(f) ?? ''),
    };
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final c in _colorControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.terminalThemeNameRequired);
      return;
    }
    // 统一校验：任一色值非法 → 整体不保存，错误显示在页面上。
    final values = <String, String>{};
    for (final entry in _colorControllers.entries) {
      final raw = entry.value.text.trim();
      try {
        TerminalColorScheme.parseHex(raw);
      } on FormatException {
        setState(() => _error =
            '${l10n.terminalThemeInvalidColor}: ${entry.key} "$raw"');
        return;
      }
      values[entry.key] = raw;
    }

    final existing = widget.initial;
    // 新建 id 用时间戳；编辑沿用原 id。
    final id = existing?.id ?? 'custom-${DateTime.now().millisecondsSinceEpoch}';
    var scheme = TerminalColorScheme(
      id: id,
      name: name,
      isDark: existing?.isDark ?? _guessIsDark(values),
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

    await ref.read(customTerminalThemesProvider.notifier).save(scheme);
    await ref.read(terminalThemeSelectionProvider.notifier).set(id);
    if (mounted) context.pop();
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.terminalThemeEdit)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
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
          // 错误信息显式展示（非法 hex / 空名称），不做静默兜底。
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: theme.textTheme.small
                    .copyWith(color: theme.colorScheme.destructive),
              ),
            ),
          const SizedBox(height: 16),
          ShadButton(
            onPressed: _save,
            child: Text(l10n.save),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 单个颜色行：色块（实时预览）+ 字段名 + hex 输入。
class _ColorFieldRow extends StatelessWidget {
  const _ColorFieldRow({
    required this.fieldKey,
    required this.controller,
  });

  final String fieldKey;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
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
                  border: Border.all(color: theme.colorScheme.border),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(fieldKey, style: theme.textTheme.small)),
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
