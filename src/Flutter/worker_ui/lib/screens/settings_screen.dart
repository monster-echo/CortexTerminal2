import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import '../core/corterm_service.dart';
import '../core/settings.dart';
import '../l10n/app_strings.dart';
import '../widgets/section_header.dart';
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
          appBar: AppBar(title: Text(title)),
          body: screen,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.t;
    final scheme = Theme.of(context).colorScheme;
    final s = Settings.instance;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(title: t(context, 'settings.title')),
          const SizedBox(height: 16),
          // 管理：认证 / 服务 / 更新 / 诊断 / 会话（从设置里进，简化主导航）
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.login, color: scheme.secondary),
                  title: Text(t(context, 'nav.auth')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(
                    context,
                    AuthScreen(service: widget.service),
                    t(context, 'nav.auth'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.memory, color: scheme.secondary),
                  title: Text(t(context, 'nav.agentTools')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(
                    context,
                    const AgentToolsScreen(),
                    t(context, 'nav.agentTools'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.system_update_alt, color: scheme.secondary),
                  title: Text(t(context, 'nav.update')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(
                    context,
                    UpdateScreen(service: widget.service),
                    t(context, 'nav.update'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.health_and_safety_outlined, color: scheme.secondary),
                  title: Text(t(context, 'nav.doctor')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(
                    context,
                    DoctorScreen(service: widget.service),
                    t(context, 'nav.doctor'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.timeline_outlined, color: scheme.secondary),
                  title: Text(t(context, 'nav.sessions')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(
                    context,
                    SessionsScreen(service: widget.service),
                    t(context, 'nav.sessions'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(t(context, 'settings.theme'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(value: ThemeMode.system, label: Text(t(context, 'settings.theme.system'))),
              ButtonSegment(value: ThemeMode.light, label: Text(t(context, 'settings.theme.light'))),
              ButtonSegment(value: ThemeMode.dark, label: Text(t(context, 'settings.theme.dark'))),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (sel) => s.setThemeMode(sel.first),
          ),
          const SizedBox(height: 24),
          Text(t(context, 'settings.language'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButton<String>(
            value: s.locale,
            items: const [
              DropdownMenuItem(value: 'zh', child: Text('中文')),
              DropdownMenuItem(value: 'en', child: Text('English')),
            ],
            onChanged: (v) {
              if (v != null) s.setLocale(v);
            },
          ),
          const SizedBox(height: 16),
          Card(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: Text(t(context, 'settings.launchAtStartup'), style: const TextStyle(fontSize: 15)),
              subtitle: Text(
                t(context, 'settings.launchAtStartupHint'),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              value: _launchAtStartup ?? false,
              onChanged: _launchAtStartup == null ? null : _toggleLaunchAtStartup,
            ),
          ),
          if (_startupError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_startupError!, style: TextStyle(color: scheme.error, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
