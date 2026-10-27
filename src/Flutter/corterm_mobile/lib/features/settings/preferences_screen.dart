import '../../shared/layout/adaptive_page_scaffold.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/storage/app_preferences.dart';
import '../../core/models/terminal_color_scheme.dart';
import '../../app/theme/corterm_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/list_group.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/sheets_and_dialogs.dart';
import '../../shared/layout/adaptive_sheet.dart';
import 'data/preferences_repository.dart';
import 'terminal_themes_screen.dart';

/// 通用偏好（设置二级页）：外观主题 / 语言 / 屏幕常亮 / 终端字号 / 回滚配额。
class PreferencesScreen extends ConsumerWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final themeMode = ref.watch(themeModeProvider);
    final terminalThemeSelection = ref.watch(terminalThemeSelectionProvider);
    final customThemes = ref.watch(customTerminalThemesProvider);
    final localeTag = ref.watch(localeProvider);
    final fontSize = ref.watch(fontSizeProvider);

    return AdaptivePageScaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          AppGroupHeader(l10n.appearance),
          AppGroupCard(
            children: [
              _PreferenceChoiceRow(
                label: l10n.appearance,
                choice: _SegmentedChoice<ThemeMode>(
                  value: themeMode,
                  options: [
                    (ThemeMode.light, l10n.appearanceLight),
                    (ThemeMode.dark, l10n.appearanceDark),
                    (ThemeMode.system, l10n.appearanceSystem),
                  ],
                  onChanged: (value) =>
                      ref.read(themeModeProvider.notifier).set(value),
                ),
              ),
              _PreferenceChoiceRow(
                label: l10n.language,
                choice: _SegmentedChoice<String>(
                  value: localeTag ?? '',
                  options: [
                    ('zh', l10n.languageChinese),
                    ('en', l10n.languageEnglish),
                    ('', l10n.languageSystem),
                  ],
                  onChanged: (value) =>
                      ref.read(localeProvider.notifier).set(value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppGroupCard(
            children: [
              AppRow(
                icon: LucideIcons.terminal,
                label: l10n.terminalTheme,
                value: terminalThemeSelectionLabel(
                  terminalThemeSelection,
                  customThemes,
                  l10n,
                ),
                chevron: true,
                onTap: () => context.push('/settings/terminal-themes'),
              ),
            ],
          ),
          AppGroupHeader(l10n.terminal),
          AppGroupCard(
            children: [
              AppRow(
                icon: LucideIcons.monitorSmartphone,
                label: l10n.keepScreenAwake,
                trailing: ShadSwitch(
                  value: ref.watch(keepAwakeProvider),
                  onChanged: (v) => ref.read(keepAwakeProvider.notifier).set(v),
                ),
              ),
              AppRow(
                icon: LucideIcons.type,
                label: l10n.terminalFontSize,
                value: l10n.fontSizeFmt(fontSize),
                trailing: SizedBox(
                  width: 140,
                  child: ShadSlider(
                    initialValue: fontSize,
                    min: AppPreferences.minFontSize,
                    max: AppPreferences.maxFontSize,
                    divisions:
                        (AppPreferences.maxFontSize -
                                AppPreferences.minFontSize)
                            .round(),
                    onChanged: (v) =>
                        ref.read(fontSizeProvider.notifier).set(v),
                  ),
                ),
              ),
              AppRow(
                icon: Icons.keyboard_outlined,
                label: Localizations.localeOf(context).languageCode == 'zh'
                    ? '终端快捷键'
                    : 'Terminal accessory keys',
                chevron: true,
                onTap: () => showAdaptiveModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const _TerminalKeysEditor(),
                ),
              ),
              _ScrollbackRow(),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            Localizations.localeOf(context).languageCode == 'zh'
                ? '偏好修改会立即生效。恢复默认仅重置本机外观、语言和终端设置，不删除会话或自定义主题。'
                : 'Changes apply immediately. Reset affects local appearance, language and terminal preferences, and keeps sessions and custom themes.',
          ),
          TextButton(
            onPressed: () async {
              final zh = Localizations.localeOf(context).languageCode == 'zh';
              final confirmed = await showConfirmDialog(
                context: context,
                title: zh ? '恢复本机默认偏好？' : 'Reset local preferences?',
                body: zh ? '会话、自定义主题和服务器回滚配额会保留。' : 'Sessions, custom themes and server scrollback quota will be kept.',
                confirmLabel: zh ? '恢复默认' : 'Reset',
              );
              if (!confirmed) return;
              try {
                await ref
                    .read(fontSizeProvider.notifier)
                    .set(AppPreferences.defaultFontSize);
                await ref.read(keepAwakeProvider.notifier).set(true);
                await ref
                    .read(terminalKeyLayoutProvider.notifier)
                    .set(terminalKeyDefaults);
                await ref
                    .read(terminalThemeSelectionProvider.notifier)
                    .set(followAppTerminalTheme);
                await ref.read(directoryCollapsedProvider.notifier).set(false);
                await ref
                    .read(themeModeProvider.notifier)
                    .set(ThemeMode.system);
                await ref.read(localeProvider.notifier).set('');
                if (context.mounted) showAppToast(context, l10n.saved);
              } catch (error) {
                if (context.mounted) {
                  showAppToast(context, '$error', destructive: true);
                }
              }
            },
            child: Text(
              Localizations.localeOf(context).languageCode == 'zh'
                  ? '恢复默认偏好'
                  : 'Reset local preferences',
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 服务端 scrollback 配额（Segment 选择，对齐 MAUI 设置页）。
/// 控制 Worker 重放窗口；客户端 xterm 缓冲恒为 64000 行。
class _ScrollbackRow extends ConsumerWidget {
  static const _options = <int, String>{
    524288: '512K',
    1048576: '1M',
    2097152: '2M',
    5242880: '5M',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pref = ref.watch(scrollbackPreferenceProvider);

    return _PreferenceChoiceRow(
      label: l10n.scrollbackQuota,
      choice: pref.when(
        loading: () => const SizedBox(
          width: 14,
          height: 14,
          child: ShadProgress(value: null),
        ),
        error: (e, _) => TextButton(
          onPressed: () => ref.invalidate(scrollbackPreferenceProvider),
          child: Text(l10n.retry),
        ),
        data: (p) {
          // 服务端可能存有非预设值（web 端设置过）：如实展示，不冒充预设档位。
          final options = Map<int, String>.of(_options);
          if (!options.containsKey(p.maxBytes)) {
            options[p.maxBytes] = p.maxBytes % 1048576 == 0
                ? '${p.maxBytes ~/ 1048576}M'
                : '${p.maxBytes ~/ 1024}K';
          }
          return _SegmentedChoice<int>(
            value: p.maxBytes,
            options: [
              for (final entry in options.entries) (entry.key, entry.value),
            ],
            onChanged: (v) async {
              if (v == p.maxBytes) return;
              try {
                await ref
                    .read(preferencesRepositoryProvider)
                    .updateScrollback(maxBytes: v);
                ref.invalidate(scrollbackPreferenceProvider);
                if (context.mounted) showAppToast(context, l10n.saved);
              } catch (e) {
                if (context.mounted) {
                  showAppToast(context, '$e', destructive: true);
                }
              }
            },
          );
        },
      ),
    );
  }
}

class _PreferenceChoiceRow extends StatelessWidget {
  const _PreferenceChoiceRow({required this.label, required this.choice});

  final String label;
  final Widget choice;

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    final labelWidget = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 15, color: colors.textPrimary),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 350 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.15;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    labelWidget,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: choice),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: labelWidget),
                    const SizedBox(width: 8),
                    choice,
                  ],
                ),
        );
      },
    );
  }
}

class _SegmentedChoice<T> extends StatelessWidget {
  const _SegmentedChoice({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    return Wrap(
      alignment: WrapAlignment.end,
      children: [
        for (final option in options)
          Semantics(
            selected: option.$1 == value,
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onChanged(option.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
                decoration: BoxDecoration(
                  color: option.$1 == value
                      ? colors.surfaceSelected
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  option.$2,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: option.$1 == value
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: option.$1 == value
                        ? colors.textPrimary
                        : colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TerminalKeysEditor extends ConsumerStatefulWidget {
  const _TerminalKeysEditor();
  @override
  ConsumerState<_TerminalKeysEditor> createState() =>
      _TerminalKeysEditorState();
}

class _TerminalKeysEditorState extends ConsumerState<_TerminalKeysEditor> {
  late final List<String> _keys = [
    ...ref.read(terminalKeyLayoutProvider),
    ...terminalKeyDefaults.where(
      (key) => !ref.read(terminalKeyLayoutProvider).contains(key),
    ),
  ];
  late final Set<String> _enabled = ref.read(terminalKeyLayoutProvider).toSet();
  bool _saving = false;
  String? _error;
  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    const labels = {
      'esc': 'Esc',
      'ctrl': 'Ctrl',
      'alt': 'Alt',
      'tab': 'Tab',
      'shiftTab': 'Shift + Tab',
      'left': '←',
      'up': '↑',
      'down': '↓',
      'right': '→',
      'paste': 'Paste',
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            zh ? '终端快捷键' : 'Terminal accessory keys',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            zh ? '勾选常用按键，用箭头调整顺序。“完成”始终保留。' : 'Choose keys and use arrows to reorder. Done always stays visible.',
          ),
          for (var index = 0; index < _keys.length; index++)
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      _keys[index] == 'paste'
                          ? AppLocalizations.of(context)!.paste
                          : labels[_keys[index]]!,
                    ),
                    value: _enabled.contains(_keys[index]),
                    onChanged: _saving
                        ? null
                        : (selected) => setState(() {
                            if (selected == true) {
                              _enabled.add(_keys[index]);
                            } else {
                              _enabled.remove(_keys[index]);
                            }
                          }),
                  ),
                ),
                IconButton(
                  tooltip: zh ? '上移' : 'Move up',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: _saving || index == 0
                      ? null
                      : () => setState(() {
                          final key = _keys.removeAt(index);
                          _keys.insert(index - 1, key);
                        }),
                ),
                IconButton(
                  tooltip: zh ? '下移' : 'Move down',
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: _saving || index == _keys.length - 1
                      ? null
                      : () => setState(() {
                          final key = _keys.removeAt(index);
                          _keys.insert(index + 1, key);
                        }),
                ),
              ],
            ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: colorsOf(context).danger)),
          FilledButton(
            onPressed: _saving || _enabled.isEmpty
                ? null
                : () async {
                    setState(() => _saving = true);
                    try {
                      await ref
                          .read(terminalKeyLayoutProvider.notifier)
                          .set(_keys.where(_enabled.contains).toList());
                      if (context.mounted) Navigator.of(context).pop();
                    } catch (error) {
                      if (mounted) setState(() => _error = '$error');
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: Text(AppLocalizations.of(context)!.save),
          ),
        ],
      ),
    );
  }
}
