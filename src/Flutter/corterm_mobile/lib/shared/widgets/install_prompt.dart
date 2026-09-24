import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/app_localizations.dart';
import 'states.dart';
import '../../app/theme/corterm_theme.dart';

/// 安装命令（对齐 MAUI Session/WorkerInstallPrompt）。
const bashInstallCommand = 'curl -fsSL https://corterm.rwecho.top/install.sh | sh';
const psInstallCommand =
    'powershell -Command "irm https://corterm.rwecho.top/install.ps1 | iex"';

/// 安装引导卡片：终端风格命令块 + 复制按钮。空态（无会话/无 Worker）时展示。
class InstallPromptCard extends StatelessWidget {
  const InstallPromptCard({super.key, required this.title, required this.intro});

  final String title;
  final String intro;

  static void showSheet(BuildContext context,
      {required String title, required String intro}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom),
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ShadTheme.of(context).colorScheme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ShadTheme.of(context).colorScheme.border),
          ),
          child: InstallPromptCard(title: title, intro: intro),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: scheme.foreground)),
        const SizedBox(height: 6),
        Text(intro,
            style: TextStyle(fontSize: 13, color: scheme.mutedForeground, height: 1.5)),
        const SizedBox(height: 12),
        _CommandBlock(label: 'macOS / Linux', command: bashInstallCommand),
        const SizedBox(height: 8),
        _CommandBlock(label: 'Windows (PowerShell)', command: psInstallCommand),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(LucideIcons.keySquare, size: 15, color: scheme.mutedForeground),
            const SizedBox(width: 6),
            Expanded(
              child: Text(l10n.installActivateHint,
                  style: TextStyle(fontSize: 12, color: scheme.mutedForeground)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: () {
            Clipboard.setData(const ClipboardData(text: bashInstallCommand));
            showAppToast(context, l10n.copied);
          },
          child: Text(l10n.installCopyCommand),
        ),
      ],
    );
  }
}

class _CommandBlock extends StatelessWidget {
  const _CommandBlock({required this.label, required this.command});

  final String label;
  final String command;

  @override
  Widget build(BuildContext context) {
    // 终端风格配色固定（不随主题）：深底浅字，命令块语义即"远端终端"。
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: CortermColors.darkTool.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(
              children: [
                _dot(CortermColors.darkTool.danger),
                const SizedBox(width: 5),
                _dot(CortermColors.darkTool.warning),
                const SizedBox(width: 5),
                _dot(CortermColors.darkTool.success),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(fontSize: 11, color: CortermColors.darkTool.textSecondary)),
                const Spacer(),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: command));
                    showAppToast(context, AppLocalizations.of(context)!.copied);
                  },
                  child: Icon(LucideIcons.copy, size: 14, color: CortermColors.darkTool.textSecondary),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: SelectableText(
              '\$ $command',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: CortermColors.darkTool.textPrimary,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
