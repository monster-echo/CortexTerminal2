import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/corterm_service.dart';
import '../core/app_scope.dart';
import '../core/models.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bar.dart';
import '../widgets/error_banner.dart';
import '../widgets/list_group.dart';

/// 诊断页：进入即自动运行，清单本身就是结论（✓/✗ + 一行说明）。
/// 唯一操作「重新运行」收在导航栏右侧，不与结果争夺注意力。
class DoctorScreen extends StatefulWidget {
  const DoctorScreen({super.key});

  @override
  State<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends State<DoctorScreen> {
  late CortermService _service;
  bool _started = false;
  DoctorResult? _result;
  String? _error;
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _service = AppScope.of(context).service;
    if (!_started) {
      _started = true;
      _run();
    }
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final r = await _service.doctor();
      if (!mounted) return;
      setState(() {
        _result = r;
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.t;
    final scheme = ShadTheme.of(context).colorScheme;
    return Scaffold(
      appBar: WorkerAppBar(
        title: t(context, 'doctor.title'),
        actions: [
          if (!_running)
            ShadIconButton.ghost(
              onPressed: _run,
              icon: Icon(LucideIcons.refreshCw, size: 18),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ErrorBanner(message: _error),
            if (_running)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: _RunningIndicator()))
            else if (_result != null)
              AppGroupCard(
                children: [
                  for (var i = 0; i < _result!.checks.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    Builder(
                      builder: (context) {
                        final c = _result!.checks[i];
                        return AppRow(
                          icon: c.ok ? LucideIcons.circleCheck : LucideIcons.circleX,
                          iconColor: c.ok ? scheme.tertiary : scheme.destructive,
                          label: c.name,
                          value: c.detail,
                        );
                      },
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 运行中的极简占位：一条安静的 spinner，不需要文案。
class _RunningIndicator extends StatelessWidget {
  const _RunningIndicator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2.5),
    );
  }
}
