import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/binary_locator.dart';
import '../core/corterm_service.dart';
import '../core/settings.dart';
import '../l10n/app_strings.dart';
import '../widgets/app_nav_rail.dart';
import '../widgets/error_banner.dart';
import 'dashboard_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  CortermService? _service;
  String? _error;

  @override
  void initState() {
    super.initState();
    Settings.instance.addListener(_resolve);
    _resolve();
  }

  @override
  void dispose() {
    Settings.instance.removeListener(_resolve);
    super.dispose();
  }

  Future<void> _resolve() async {
    final paths = await resolveBinaryPaths();
    if (!mounted) return;
    if (paths == null) {
      setState(() {
        _service = null;
        _error = AppStrings.of(Settings.instance.locale, 'binaryLocator.notFound');
      });
      return;
    }
    setState(() {
      _service = CortermService(cortermPath: paths.corterm, cortapPath: paths.cortap);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.t;
    final scheme = ShadTheme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          AppNavRail(
            items: [
              AppNavItem(LucideIcons.layoutDashboard, t(context, 'nav.dashboard')),
              AppNavItem(LucideIcons.settings, t(context, 'nav.settings')),
            ],
            index: _index,
            onSelect: (i) => setState(() => _index = i),
          ),
          VerticalDivider(width: 1, color: scheme.border),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final service = _service;
    if (service == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ErrorBanner(message: _error, onRetry: _resolve),
        ),
      );
    }
    switch (_index) {
      case 0:
        return DashboardScreen(service: service);
      case 1:
        return SettingsScreen(service: service);
      default:
        return DashboardScreen(service: service);
    }
  }
}
