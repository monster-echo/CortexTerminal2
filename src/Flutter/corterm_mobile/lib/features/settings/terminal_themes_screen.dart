import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/models/terminal_color_scheme.dart';
import '../../core/storage/app_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/list_group.dart';
import '../../shared/widgets/sheets_and_dialogs.dart';

/// 终端主题管理页（外观入口）：内置预设 + 自定义主题，点选即生效。
class TerminalThemesScreen extends ConsumerWidget {
  const TerminalThemesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final selection = ref.watch(terminalThemeSelectionProvider);
    final customs = ref.watch(customTerminalThemesProvider);

    Widget themeTile(TerminalColorScheme scheme, {bool custom = false}) {
      final selected = selection == scheme.id;
      return AppRow(
        leadingWidget: _SchemePreview(scheme: scheme),
        label: terminalThemeDisplayName(scheme, l10n),
        onTap: () =>
            ref.read(terminalThemeSelectionProvider.notifier).set(scheme.id),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (custom) ...[
              ShadIconButton.ghost(
                icon: const Icon(LucideIcons.squarePen, size: 16),
                onPressed: () => context.push(
                  '/settings/terminal-themes/edit',
                  extra: scheme,
                ),
              ),
              ShadIconButton.ghost(
                icon: Icon(LucideIcons.trash,
                    size: 16, color: ShadTheme.of(context).colorScheme.destructive),
                onPressed: () => _confirmDelete(context, ref, scheme),
              ),
            ],
            if (selected)
              Icon(LucideIcons.check,
                  size: 18, color: ShadTheme.of(context).colorScheme.primary),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.terminalTheme)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          AppGroupHeader(l10n.terminalThemeBuiltinSection),
          AppGroupCard(
            children: [
              for (final scheme in builtinTerminalColorSchemes)
                themeTile(scheme),
            ],
          ),
          AppGroupHeader(l10n.terminalThemeCustomSection),
          AppGroupCard(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (customs.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Text(
                    l10n.terminalThemeCustomEmpty,
                    style: ShadTheme.of(context)
                        .textTheme
                        .small
                        .copyWith(color: ShadTheme.of(context).colorScheme.mutedForeground),
                  ),
                )
              else
                for (final scheme in customs) themeTile(scheme, custom: true),
              AppRow(
                icon: LucideIcons.plus,
                label: l10n.terminalThemeCustomNew,
                onTap: () =>
                    context.push('/settings/terminal-themes/edit'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    TerminalColorScheme scheme,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.terminalThemeDeleteConfirmTitle,
      body: l10n.terminalThemeDeleteConfirmBody,
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(customTerminalThemesProvider.notifier).delete(scheme.id);
    // 删除的是当前选中项 → 回到跟随 App。
    if (ref.read(terminalThemeSelectionProvider) == scheme.id) {
      await ref
          .read(terminalThemeSelectionProvider.notifier)
          .set(followAppTerminalTheme);
    }
  }
}

/// 主题显示名：内置主题名走 l10n；自定义主题用用户起的名字。
String terminalThemeDisplayName(
  TerminalColorScheme scheme,
  AppLocalizations l10n,
) =>
    switch (scheme.id) {
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
      width: 56,
      height: 32,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: scheme.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ShadTheme.of(context).colorScheme.border,
        ),
      ),
      child: Row(
        children: [
          Text(
            'Aa',
            style: ShadTheme.of(context).textTheme.small.copyWith(
                  color: scheme.foregroundColor,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const Spacer(),
          chip(scheme.red),
          const SizedBox(width: 3),
          chip(scheme.green),
          const SizedBox(width: 3),
          chip(scheme.blue),
        ],
      ),
    );
  }
}
