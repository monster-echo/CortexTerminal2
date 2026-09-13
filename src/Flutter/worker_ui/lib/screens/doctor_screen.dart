import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/corterm_service.dart';
import '../core/models.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/error_banner.dart';
import '../widgets/list_group.dart';
import '../widgets/primary_button.dart';
import '../widgets/section_header.dart';

class DoctorScreen extends StatefulWidget {
  const DoctorScreen({super.key, required this.service});

  final CortermService service;

  @override
  State<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends State<DoctorScreen> {
  DoctorResult? _result;
  String? _error;
  bool _running = false;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final r = await widget.service.doctor();
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
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(
            title: t(context, 'doctor.title'),
            trailing: PrimaryButton(
              label: t(context, 'doctor.run'),
              onPressed: _running ? null : _run,
              icon: LucideIcons.play,
            ),
          ),
          const SizedBox(height: 16),
          ErrorBanner(message: _error),
          if (_result != null) ...[
            const SizedBox(height: 16),
            Text(
              '${t(context, 'doctor.passed')}: ${_result!.passedCount}   '
              '${t(context, 'doctor.failed')}: ${_result!.failedCount}',
              style: TextStyle(
                color: _result!.failedCount == 0 ? scheme.tertiary : scheme.destructive,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
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
            if (_result!.failedCount == 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  t(context, 'doctor.allPassed'),
                  style: TextStyle(color: scheme.tertiary, fontWeight: FontWeight.w600),
                ),
              ),
          ] else if (!_running)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                t(context, 'doctor.notRun'),
                style: TextStyle(color: scheme.mutedForeground, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }
}
