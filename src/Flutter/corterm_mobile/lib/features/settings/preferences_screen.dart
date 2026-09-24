import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/storage/app_preferences.dart';
import '../../app/theme/corterm_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/list_group.dart';
import '../../shared/widgets/states.dart';
import 'data/preferences_repository.dart';
import 'terminal_themes_screen.dart';

/// 通用偏好（设置二级页）：外观主题 / 语言 / 屏幕常亮 / 终端字号 / 回滚配额。
class PreferencesScreen extends ConsumerWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final terminalThemeSelection = ref.watch(terminalThemeSelectionProvider);
    final customThemes = ref.watch(customTerminalThemesProvider);
    final localeTag = ref.watch(localeProvider);
    final fontSize = ref.watch(fontSizeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appearance)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          AppGroupCard(children: [
            // 外观主题固定 Light（design/07 Light App Context），不提供切换。
            AppRow(
              icon: LucideIcons.terminal,
              label: l10n.terminalTheme,
              value: terminalThemeSelectionLabel(
                terminalThemeSelection, customThemes, l10n),
              chevron: true,
              onTap: () => context.push('/settings/terminal-themes'),
            ),
            AppRow(
              icon: LucideIcons.globe,
              label: l10n.language,
              trailing: ShadSelect<String>(
                initialValue: localeTag ?? '',
                options: [
                  const ShadOption(value: '', child: Text('System')),
                  const ShadOption(value: 'en', child: Text('English')),
                  const ShadOption(value: 'zh', child: Text('简体中文')),
                ],
                selectedOptionBuilder: (context, value) => Text(switch (value) {
                  'en' => l10n.languageEnglish,
                  'zh' => l10n.languageChinese,
                  _ => l10n.languageSystem,
                }),
                onChanged: (v) => ref.read(localeProvider.notifier).set(v),
              ),
            ),
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
                  divisions: (AppPreferences.maxFontSize - AppPreferences.minFontSize).round(),
                  onChanged: (v) => ref.read(fontSizeProvider.notifier).set(v),
                ),
              ),
            ),
            _ScrollbackRow(),
          ]),
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

    return AppRow(
      icon: LucideIcons.history,
      label: l10n.scrollbackQuota,
      trailing: pref.when(
        loading: () => const SizedBox(
          width: 14,
          height: 14,
          child: ShadProgress(value: null),
        ),
        error: (e, _) => Text('—', style: TextStyle(color: colorsOf(context).textSecondary)),
        data: (p) {
          // 服务端可能存有非预设值（web 端设置过）：如实展示，不冒充预设档位。
          final options = Map<int, String>.of(_options);
          if (!options.containsKey(p.maxBytes)) {
            options[p.maxBytes] =
                p.maxBytes % 1048576 == 0 ? '${p.maxBytes ~/ 1048576}M' : '${p.maxBytes ~/ 1024}K';
          }
          return ShadSelect<int>(
            initialValue: p.maxBytes,
            options: [
              for (final entry in options.entries)
                ShadOption(value: entry.key, child: Text(entry.value)),
            ],
            selectedOptionBuilder: (context, value) => Text(options[value] ?? '$value'),
            onChanged: (v) async {
              if (v == null || v == p.maxBytes) return;
              try {
                await ref.read(preferencesRepositoryProvider).updateScrollback(maxBytes: v);
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


