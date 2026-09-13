import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/corterm_service.dart';
import '../core/models.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/error_banner.dart';
import '../widgets/list_group.dart';
import '../widgets/section_header.dart';
import '../widgets/states.dart';
import 'session_detail_screen.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key, required this.service});

  final CortermService service;

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  List<SessionSummary>? _sessions;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sessions = await widget.service.sessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _formatStart(String? iso) {
    if (iso == null) return '—';
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
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
            title: t(context, 'sessions.title'),
            trailing: ShadIconButton.ghost(
              onPressed: _load,
              icon: Icon(LucideIcons.refreshCw, size: 18),
            ),
          ),
          const SizedBox(height: 8),
          ErrorBanner(message: _error),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: SmallSpinner()))
          else if (_sessions == null || _sessions!.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                t(context, 'sessions.empty'),
                style: TextStyle(color: scheme.mutedForeground, fontSize: 14),
              ),
            )
          else
            AppGroupCard(
              children: [
                for (var i = 0; i < _sessions!.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Builder(
                    builder: (context) {
                      final s = _sessions![i];
                      final statusColor = s.isActive
                          ? scheme.tertiary
                          : s.isCrashed
                              ? scheme.destructive
                              : scheme.mutedForeground;
                      return AppRow(
                        icon: LucideIcons.terminal,
                        label: s.sessionId,
                        value:
                            '${s.kind}  ·  ${_formatStart(s.startedAt)}  ·  '
                            '${s.eventCount} ${t(context, 'sessions.events')}'
                            '${s.cwd.isNotEmpty ? '  ·  $s.cwd' : ''}',
                        trailing: Text(
                          t(context, 'sessions.${s.statusLabel}'),
                          style: TextStyle(color: statusColor, fontSize: 13),
                        ),
                        leadingWidget: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: s.isActive
                                ? scheme.tertiary
                                : s.isCrashed
                                    ? scheme.destructive
                                    : scheme.border,
                            shape: BoxShape.circle,
                          ),
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SessionDetailScreen(
                              service: widget.service,
                              session: s,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
