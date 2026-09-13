import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/corterm_service.dart';
import '../core/models.dart';
import '../l10n/app_strings.dart';
import '../widgets/app_bar.dart';
import '../widgets/error_banner.dart';
import '../widgets/states.dart';

/// 会话日志查看器：每 2s 轮询 `cortap events --json --last N`，Dart 侧按 EventFormatter
/// 逻辑渲染，自动滚底，可暂停/恢复实时。
class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({super.key, required this.service, required this.session});

  final CortermService service;
  final SessionSummary session;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  final ScrollController _scroll = ScrollController();
  final List<CortermEvent> _events = [];
  Timer? _timer;
  bool _live = true;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _poll();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _poll() async {
    try {
      final fresh = await widget.service.events(widget.session.sessionId, last: 200);
      if (!mounted) return;
      setState(() {
        _events
          ..clear()
          ..addAll(fresh);
        _error = null;
      });
      _autoScroll();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _autoScroll() {
    if (!_live) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.t;
    final scheme = ShadTheme.of(context).colorScheme;
    return Scaffold(
      appBar: WorkerAppBar(
        titleWidget: Text(
          widget.session.sessionId,
          style: const TextStyle(fontSize: 16, fontFamily: 'monospace'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ShadButton.ghost(
              onPressed: () => setState(() => _live = !_live),
              trailing: Icon(
                _live ? LucideIcons.circlePause : LucideIcons.circlePlay,
                size: 16,
              ),
              child: Text(_live ? t(context, 'sessionDetail.liveOn') : t(context, 'sessionDetail.liveOff')),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ErrorBanner(message: _error),
            if (_loading)
              const Expanded(child: SmallSpinner())
            else if (_events.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    t(context, 'sessionDetail.empty'),
                    style: TextStyle(color: scheme.mutedForeground),
                  ),
                ),
              )
            else
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: _events.length,
                    itemBuilder: (context, i) {
                      final e = _events[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          e.formatted,
                          style: const TextStyle(fontSize: 13, fontFamily: 'monospace', height: 1.3),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
