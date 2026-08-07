import 'package:flutter/material.dart';

import '../core/corterm_service.dart';
import '../core/models.dart';
import '../l10n/app_strings.dart';
import '../widgets/error_banner.dart';
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
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(
            title: t(context, 'doctor.title'),
            trailing: PrimaryButton(
              label: t(context, 'doctor.run'),
              onPressed: _running ? null : _run,
              icon: Icons.play_arrow,
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
                color: _result!.failedCount == 0 ? scheme.tertiary : scheme.error,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ..._result!.checks.map(
              (c) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    c.ok ? Icons.check_circle_outline : Icons.cancel_outlined,
                    color: c.ok ? scheme.tertiary : scheme.error,
                  ),
                  title: Text(c.name, style: const TextStyle(fontSize: 15)),
                  subtitle: Text(c.detail, style: const TextStyle(fontSize: 13)),
                ),
              ),
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
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }
}
