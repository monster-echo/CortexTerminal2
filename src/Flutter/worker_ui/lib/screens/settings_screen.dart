import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/corterm_service.dart';
import '../core/self_updater.dart';
import '../core/settings.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bar.dart';
import '../widgets/list_group.dart';
import '../widgets/section_header.dart';
import 'about_screen.dart';
import 'agent_tools_screen.dart';
import 'auth_screen.dart';
import 'doctor_screen.dart';
import 'sessions_screen.dart';
import 'update_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.service});

  final CortermService service;

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

  /// 从设置里进入功能页（带返回栏）。
  void _open(BuildContext context, Widget screen, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: WorkerAppBar(title: title),
          body: screen,
        ),
      ),
    );
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
          SectionHeader(title: t(context, 'settings.title')),
          const SizedBox(height: 16),
          // 管理：认证 / 服务 / 更新 / 诊断 / 会话（从设置里进，简化主导航）
          AppGroupCard(
            children: [
              AppRow(
                icon: LucideIcons.logIn,
                iconColor: scheme.link,
                label: t(context, 'nav.auth'),
                chevron: true,
                onTap: () => _open(context, AuthScreen(service: widget.service), t(context, 'nav.auth')),
              ),
              const Divider(height: 1),
              AppRow(
                icon: LucideIcons.cpu,
                iconColor: scheme.link,
                label: t(context, 'nav.agentTools'),
                chevron: true,
                onTap: () =>
                    _open(context, const AgentToolsScreen(), t(context, 'nav.agentTools')),
              ),
              const Divider(height: 1),
              AppRow(
                icon: LucideIcons.download,
                iconColor: scheme.link,
                label: t(context, 'nav.update'),
                chevron: true,
                onTap: () =>
                    _open(context, UpdateScreen(service: widget.service), t(context, 'nav.update')),
              ),
              const Divider(height: 1),
              AppRow(
                icon: LucideIcons.shieldCheck,
                iconColor: scheme.link,
                label: t(context, 'nav.doctor'),
                chevron: true,
                onTap: () =>
                    _open(context, DoctorScreen(service: widget.service), t(context, 'nav.doctor')),
              ),
              const Divider(height: 1),
              AppRow(
                icon: LucideIcons.activity,
                iconColor: scheme.link,
                label: t(context, 'nav.sessions'),
                chevron: true,
                onTap: () => _open(
                  context,
                  SessionsScreen(service: widget.service),
                  t(context, 'nav.sessions'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
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
          const SizedBox(height: 24),
          // 关于：版本 / 版权 / worker 版本 / 主页
          AppGroupCard(
            children: [
              AppRow(
                icon: LucideIcons.info,
                iconColor: scheme.link,
                label: t(context, 'about.title'),
                value: 'v$appVersion',
                chevron: true,
                onTap: () => _open(context, const AboutScreen(), t(context, 'about.title')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
