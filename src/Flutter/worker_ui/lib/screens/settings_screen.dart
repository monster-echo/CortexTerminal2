import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/settings.dart';
import '../l10n/app_strings.dart';
import '../widgets/list_group.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _launchAtStartup; // null = 尚未读取到系统状态
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _loadLaunchAtStartup();
  }

  Future<void> _loadLaunchAtStartup() async {
    try {
      final enabled = await launchAtStartup.isEnabled();
      if (mounted) setState(() => _launchAtStartup = enabled);
    } catch (_) {
      if (mounted) setState(() => _launchAtStartup = false);
    }
  }

  Future<void> _toggleLaunchAtStartup(bool value) async {
    setState(() => _startupError = null);
    try {
      if (value) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
      if (mounted) setState(() => _launchAtStartup = value);
    } catch (_) {
      if (mounted) {
        setState(() => _startupError = AppStrings.t(context, 'settings.launchAtStartupError'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.t;
    final s = Settings.instance;
    final scheme = ShadTheme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 偏好设置：主题 / 语言 / 开机启动。
          // 会话、诊断、更新等管理入口已上移概览面板；关于也在面板，此处不再重复。
          Text(t(context, 'settings.theme'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ShadTabs<ThemeMode>(
            value: s.themeMode,
            maintainState: false,
            onChanged: s.setThemeMode,
            tabs: [
              for (final m in ThemeMode.values)
                ShadTab<ThemeMode>(
                  value: m,
                  content: null,
                  child: Text(
                    switch (m) {
                      ThemeMode.system => t(context, 'settings.theme.system'),
                      ThemeMode.light => t(context, 'settings.theme.light'),
                      ThemeMode.dark => t(context, 'settings.theme.dark'),
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(t(context, 'settings.language'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ShadSelect<String>(
            initialValue: s.locale,
            minWidth: 160,
            selectedOptionBuilder: (context, v) => Text(v == 'zh' ? '中文' : 'English'),
            options: const [
              ShadOption(value: 'zh', child: Text('中文')),
              ShadOption(value: 'en', child: Text('English')),
            ],
            onChanged: (v) {
              if (v != null) s.setLocale(v);
            },
          ),
          const SizedBox(height: 16),
          AppGroupCard(
            children: [
              AppRow(
                label: t(context, 'settings.launchAtStartup'),
                value: t(context, 'settings.launchAtStartupHint'),
                trailing: ShadSwitch(
                  value: _launchAtStartup ?? false,
                  // 与按钮同理：仅 onChanged: null 不会置灰
                  enabled: _launchAtStartup != null,
                  onChanged: _toggleLaunchAtStartup,
                ),
              ),
            ],
          ),
          if (_startupError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_startupError!, style: TextStyle(color: scheme.destructive, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
