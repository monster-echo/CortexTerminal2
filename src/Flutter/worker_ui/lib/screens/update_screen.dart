import 'dart:async';

import 'package:flutter/material.dart';

import '../core/corterm_service.dart';
import '../core/models.dart';
import '../l10n/app_strings.dart';
import '../widgets/error_banner.dart';
import '../widgets/primary_button.dart';
import '../widgets/section_header.dart';
import '../widgets/status_card.dart';

class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key, required this.service});

  final CortermService service;

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  UpdateCheck? _checkResult;
  String? _error;
  bool _checking = false;
  bool _updating = false;
  String? _doneMessage;
  final List<UpdateProgress> _stages = [];

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final r = await widget.service.updateCheck();
      if (!mounted) return;
      setState(() {
        _checkResult = r;
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _checking = false;
      });
    }
  }

  Future<void> _update() async {
    setState(() {
      _updating = true;
      _error = null;
      _doneMessage = null;
      _stages.clear();
    });
    try {
      await for (final stage in widget.service.update()) {
        if (!mounted) return;
        setState(() {
          _stages.add(stage);
          if (stage.isError) _error = stage.message ?? 'update failed';
          if (stage.isDone) _doneMessage = stage.version ?? '';
        });
        if (stage.isError || stage.isDone) break;
      }
      if (!mounted) return;
      setState(() => _updating = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _updating = false;
      });
    }
  }

  String _stageLabel(BuildContext context, String stage) {
    final t = AppStrings.t;
    switch (stage) {
      case 'check':
        return t(context, 'update.stage.check');
      case 'download':
        return t(context, 'update.stage.download');
      case 'extract':
        return t(context, 'update.stage.extract');
      case 'install':
        return t(context, 'update.stage.install');
      case 'restart':
        return t(context, 'update.stage.restart');
      case 'done':
        return t(context, 'update.stage.done');
      case 'error':
        return t(context, 'common.error');
      default:
        return stage;
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
            title: t(context, 'update.title'),
            trailing: PrimaryButton(
              label: t(context, 'update.check'),
              onPressed: _checking ? null : _checkForUpdates,
              icon: Icons.search,
            ),
          ),
          const SizedBox(height: 16),
          ErrorBanner(message: _error),
          if (_checkResult != null) ...[
            const SizedBox(height: 16),
            StatusCard(
              title: t(context, 'update.title'),
              items: [
                (t(context, 'update.current'), _checkResult!.currentVersion),
                (t(context, 'update.latest'), _checkResult!.latestVersion ?? '—'),
                (
                  t(context, 'update.available'),
                  _checkResult!.updateAvailable ? '●' : '—',
                ),
                if (_checkResult!.assetName != null)
                  (t(context, 'update.asset'), _checkResult!.assetName!),
              ],
            ),
            if (_checkResult!.updateAvailable && !_updating) ...[
              const SizedBox(height: 16),
              Text(
                t(context, 'update.restartWarn'),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: t(context, 'update.trigger'),
                onPressed: _update,
                icon: Icons.system_update_alt,
                expanded: true,
              ),
            ],
          ],
          if (_updating) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
            ..._stages.map(
              (s) => ListTile(
                dense: true,
                leading: Icon(
                  s.isError ? Icons.cancel_outlined : Icons.check_circle_outline,
                  color: s.isError ? scheme.error : scheme.tertiary,
                ),
                title: Text(_stageLabel(context, s.stage)),
                trailing: s.bytes != null && s.bytes! > 0 ? Text('${s.bytes} B') : null,
              ),
            ),
          ],
          if (_doneMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              '${t(context, 'update.stage.done')}  v$_doneMessage',
              style: TextStyle(color: scheme.tertiary, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
