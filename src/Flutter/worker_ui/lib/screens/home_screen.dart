import 'package:flutter/material.dart';

import '../core/binary_locator.dart';
import '../core/corterm_service.dart';
import '../core/settings.dart';
import '../l10n/app_strings.dart';
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
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            destinations: [
              NavigationRailDestination(
                icon: const Icon(Icons.dashboard_outlined),
                selectedIcon: const Icon(Icons.dashboard),
                label: Text(t(context, 'nav.dashboard')),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: Text(t(context, 'nav.settings')),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
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
