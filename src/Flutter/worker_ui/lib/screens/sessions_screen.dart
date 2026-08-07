import 'package:flutter/material.dart';

import '../core/corterm_service.dart';
import '../core/models.dart';
import '../l10n/app_strings.dart';
import '../widgets/error_banner.dart';
import '../widgets/section_header.dart';
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
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(
            title: t(context, 'sessions.title'),
            trailing: IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ),
          const SizedBox(height: 8),
          ErrorBanner(message: _error),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (_sessions == null || _sessions!.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                t(context, 'sessions.empty'),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
              ),
            )
          else
            ..._sessions!.map(
              (s) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 6,
                    backgroundColor: s.isActive
                        ? scheme.tertiary
                        : s.isCrashed
                            ? scheme.error
                            : scheme.outlineVariant,
                  ),
                  title: Text(s.sessionId, style: const TextStyle(fontSize: 14, fontFamily: 'monospace')),
                  subtitle: Text(
                    '${s.kind}  ·  ${_formatStart(s.startedAt)}  ·  '
                    '${s.eventCount} ${t(context, 'sessions.events')}'
                    '${s.cwd.isNotEmpty ? '  ·  $s.cwd' : ''}',
                    style: const TextStyle(fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    t(context, 'sessions.${s.statusLabel}'),
                    style: TextStyle(
                      color: s.isActive
                          ? scheme.tertiary
                          : s.isCrashed
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                      fontSize: 13,
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
                ),
              ),
            ),
        ],
      ),
    );
  }
}
