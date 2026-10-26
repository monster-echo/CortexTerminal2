import '../../shared/layout/adaptive_page_scaffold.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/sheets_and_dialogs.dart';
import '../../shared/widgets/states.dart';

import '../../core/models/terminal_color_scheme.dart';
import '../../core/storage/app_preferences.dart';
import '../../app/theme/corterm_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/list_group.dart';

/// 终端主题管理页（外观入口）：跟随应用 + 内置预设，点选即生效。
class TerminalThemesScreen extends ConsumerWidget {
  const TerminalThemesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final selection = ref.watch(terminalThemeSelectionProvider);
    final custom = ref.watch(customTerminalThemesProvider);
    final zh = Localizations.localeOf(context).languageCode == 'zh';

    Widget themeTile(TerminalColorScheme scheme) {
      final selected = selection == scheme.id;
      final c = colorsOf(context);
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: selected ? c.surfaceSelected : c.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? c.accent : c.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: AppRow(
          leadingWidget: _SchemePreview(scheme: scheme),
          label: terminalThemeDisplayName(scheme, l10n),
          onTap: () =>
              ref.read(terminalThemeSelectionProvider.notifier).set(scheme.id),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) Icon(LucideIcons.check, size: 18, color: c.accent),
              if (custom.any((item) => item.id == scheme.id)) ...[
                IconButton(
                  tooltip: zh ? '编辑主题' : 'Edit theme',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => context.push(
                    '/settings/terminal-themes/edit',
                    extra: scheme,
                  ),
                ),
                IconButton(
                  tooltip: zh ? '删除主题' : 'Delete theme',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final confirmed = await showConfirmDialog(
                      context: context,
                      title: zh ? '删除主题？' : 'Delete theme?',
                      body: scheme.name,
                      confirmLabel: l10n.delete,
                      destructive: true,
                    );
                    if (!confirmed) return;
                    try {
                      if (selection == scheme.id) {
                        await ref
                            .read(terminalThemeSelectionProvider.notifier)
                            .set(followAppTerminalTheme);
                      }
                      await ref
                          .read(customTerminalThemesProvider.notifier)
                          .delete(scheme.id);
                    } catch (error) {
                      if (context.mounted) {
                        showAppToast(context, '$error', destructive: true);
                      }
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      );
    }

    return AdaptivePageScaffold(
      appBar: AppBar(
        title: Text(l10n.terminalTheme),
        actions: [
          IconButton(
            tooltip: zh ? '新建主题' : 'New theme',
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/settings/terminal-themes/edit'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          AppGroupCard(
            children: [
              AppRow(
                leadingWidget: const Icon(LucideIcons.monitor),
                label: l10n.terminalThemeSystem,
                value: Localizations.localeOf(context).languageCode == 'zh'
                    ? '随 App 亮暗模式自动切换'
                    : 'Automatically follows the app appearance',
                trailing: selection == followAppTerminalTheme
                    ? Icon(LucideIcons.check, color: colorsOf(context).accent)
                    : null,
                onTap: () => ref
                    .read(terminalThemeSelectionProvider.notifier)
                    .set(followAppTerminalTheme),
              ),
            ],
          ),
          AppGroupHeader(zh ? '自定义主题' : 'Custom themes'),
          for (final scheme in custom) themeTile(scheme),
          if (custom.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                zh
                    ? '还没有自定义主题，使用＋创建。'
                    : 'No custom themes yet. Use + to create one.',
              ),
            ),
          AppGroupHeader(l10n.terminalThemeBuiltinSection),
          AppGroupCard(
            children: [
              for (final scheme in builtinTerminalColorSchemes)
                themeTile(scheme),
            ],
          ),
        ],
      ),
    );
  }
}

/// 主题显示名：内置主题名走 l10n；自定义主题用用户起的名字。
String terminalThemeDisplayName(
  TerminalColorScheme scheme,
  AppLocalizations l10n,
) => switch (scheme.id) {
  'default-dark' => l10n.terminalThemeDefaultDark,
  'default-light' => l10n.terminalThemeDefaultLight,
  'solarized-dark' => l10n.terminalThemeSolarizedDark,
  'solarized-light' => l10n.terminalThemeSolarizedLight,
  'nord' => l10n.terminalThemeNord,
  _ => scheme.name,
};

/// Preferences 行副标题：当前选中主题的显示名。
String terminalThemeSelectionLabel(
  String selection,
  List<TerminalColorScheme> customThemes,
  AppLocalizations l10n,
) {
  if (selection == followAppTerminalTheme) return l10n.terminalThemeSystem;
  for (final scheme in [...builtinTerminalColorSchemes, ...customThemes]) {
    if (scheme.id == selection) return terminalThemeDisplayName(scheme, l10n);
  }
  return l10n.terminalThemeSystem;
}

/// 色卡预览：迷你终端画布（背景 + 前景 "Aa_"）+ 三个语义色块。
class _SchemePreview extends StatelessWidget {
  const _SchemePreview({required this.scheme});

  final TerminalColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    Widget chip(String hex) => Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: TerminalColorScheme.parseHex(hex),
        shape: BoxShape.circle,
      ),
    );

    return Container(
      // 68 = 内容（Aa + 3×色点 + 间距 ≈ 54）+ 2×6 padding + 余量，避免 Row 溢出。
      width: 68,
      height: 32,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: scheme.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorsOf(context).divider),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          children: [
            Text(
              'Aa',
              style: ShadTheme.of(context).textTheme.small.copyWith(
                color: scheme.foregroundColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 3),
            chip(scheme.red),
            const SizedBox(width: 3),
            chip(scheme.green),
            const SizedBox(width: 3),
            chip(scheme.blue),
          ],
        ),
      ),
    );
  }
}
