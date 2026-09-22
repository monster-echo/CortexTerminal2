import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/self_updater.dart';
import '../l10n/app_strings.dart';
import '../widgets/list_group.dart';
import '../widgets/section_header.dart';

/// 关于云枢终端：应用名 / 版本 / 版权 / worker 版本 / 项目主页。
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, this.workerVersion});

  /// corterm worker 版本（TrayController 轮询的 status；取不到就不展示该行）。
  final String? workerVersion;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.t;
    final scheme = ShadTheme.of(context).colorScheme;
    final isWindows = Platform.isWindows;
    final osLabel = isWindows
        ? 'Windows'
        : Platform.isMacOS
            ? 'macOS'
            : Platform.operatingSystem;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(title: t(context, 'about.title')),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/tray_icon.png',
                    width: 72,
                    height: 72,
                    // 模板图是黑色 template 图标，浅色模式下看不见
                    color: scheme.foreground,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  t(context, 'appTitle'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'v$appVersion · $osLabel',
                  style: TextStyle(color: scheme.mutedForeground, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          AppGroupCard(
            children: [
              if (workerVersion != null) ...[
                AppRow(label: t(context, 'about.worker'), value: 'v$workerVersion'),
                const Divider(height: 1),
              ],
              AppRow(label: t(context, 'about.copyright'), value: '© 2026 Corterm'),
              const Divider(height: 1),
              AppRow(label: t(context, 'about.homepage'), value: 'github.com/monster-echo/CortexTerminal2'),
            ],
          ),
        ],
      ),
    );
  }
}
