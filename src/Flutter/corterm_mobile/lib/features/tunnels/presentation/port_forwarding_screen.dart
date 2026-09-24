import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../core/models/session.dart';
import '../../../shared/widgets/corterm_ui.dart';
import '../../../shared/widgets/states.dart' show ErrorState, showAppToast;
import '../../tunnels/data/tunnel_repository.dart';
import '../../workspaces/data/workspace_providers.dart';

/// 端口转发（Dark Tool Context，design/06）：后端隧道挂在 Session 上，
/// 此页展示当前工作区所有运行中会话的隧道并集；开 = create，关 = revoke。
class PortForwardingScreen extends ConsumerStatefulWidget {
  const PortForwardingScreen({super.key, required this.workspaceId});

  final String workspaceId;

  @override
  ConsumerState<PortForwardingScreen> createState() =>
      _PortForwardingScreenState();
}

class _SessionTunnel {
  _SessionTunnel(this.sessionId, this.sessionName, this.tunnel);
  final String sessionId;
  final String sessionName;
  final TunnelSummary tunnel;
}

class _PortForwardingScreenState extends ConsumerState<PortForwardingScreen> {
  late List<String> _runningIds;
  late Future<List<_SessionTunnel>> _future = _load();

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final sessions = ref.read(workspaceSessionsProvider(widget.workspaceId));
    _runningIds =
        sessions.where((s) => s.status.isRunning).map((s) => s.sessionId).toList();
  }

  Future<List<_SessionTunnel>> _load() async {
    final sessions = ref.read(workspaceSessionsProvider(widget.workspaceId));
    final running = sessions.where((s) => s.status.isRunning).toList();
    final results = await Future.wait(
      running.map((s) => ref.read(tunnelRepositoryProvider).list(s.sessionId)),
    );
    return [
      for (final (i, tunnels) in results.indexed)
        for (final t in tunnels)
          _SessionTunnel(running[i].sessionId, running[i].displayName, t),
    ];
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _create(int port) async {
    setState(() => _busy = true);
    try {
      await ref.read(tunnelRepositoryProvider).create(
            sessionId: _runningIds.first,
            port: port,
          );
      if (!mounted) return;
      showAppToast(context, '转发已创建并启动');
      await _refresh();
    } catch (e) {
      if (mounted) showAppToast(context, '创建失败：$e', destructive: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop(_SessionTunnel st) async {
    setState(() => _busy = true);
    try {
      await ref.read(tunnelRepositoryProvider).revoke(st.tunnel.tunnelId);
      if (!mounted) return;
      showAppToast(context, '转发已停止');
      await _refresh();
    } catch (e) {
      if (mounted) showAppToast(context, '停止失败：$e', destructive: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _confirmDelete(_SessionTunnel st) {
    final c = colorsOf(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: c.surfaceElevated,
        title: Text('删除转发规则', style: TextStyle(color: c.textPrimary)),
        content: Text(
          '端口 ${st.tunnel.port} 的转发将被删除，此操作不可撤销。',
          style: TextStyle(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('取消', style: TextStyle(color: c.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _stop(st);
            },
            child: Text('删除', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
  }

  void _copyUrl(TunnelSummary t) {
    Clipboard.setData(ClipboardData(text: t.url));
    showAppToast(context, '地址已复制');
  }

  void _showCreateSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorsOf(context).surface,
      builder: (_) => _CreateSheet(
        onSubmit: (port) {
          Navigator.of(context).pop();
          _create(port);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: cortermDarkToolTheme(),
      child: Builder(
        builder: (context) {
          final c = colorsOf(context);
          final hasRunning = _runningIds.isNotEmpty;
          return Scaffold(
            backgroundColor: c.background,
            appBar: AppBar(
              title: const Text('端口转发'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '新建转发规则',
                  onPressed: hasRunning && !_busy ? _showCreateSheet : null,
                ),
              ],
            ),
            body: !hasRunning
                ? EmptyState(
                    icon: Icons.error_outline,
                    message: '没有运行中的会话，无法使用端口转发',
                  )
                : FutureBuilder<List<_SessionTunnel>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return ErrorState(
                          message: '${snap.error}',
                          onRetry: _refresh,
                        );
                      }
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final tunnels = snap.data!;
                      if (tunnels.isEmpty) {
                        return const EmptyState(
                          icon: Icons.swap_horiz,
                          message: '暂无转发规则，点右上角 + 新建',
                        );
                      }
                      return ListView.separated(
                        itemCount: tunnels.length,
                        separatorBuilder: (_, _) =>
                            Divider(color: c.divider, height: 1, indent: 16),
                        itemBuilder: (context, i) =>
                            _TunnelTile(st: tunnels[i], screen: this),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

class _TunnelTile extends StatelessWidget {
  const _TunnelTile({required this.st, required this.screen});

  final _SessionTunnel st;
  final _PortForwardingScreenState screen;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final t = st.tunnel;
    final listening = t.portOpen;
    return ListTile(
      title: Text(
        '${t.port} → ${t.url}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 16, color: c.textPrimary),
      ),
      subtitle: Text(
        listening
            ? '${st.sessionName} · 到期 ${_fmtExpire(t.expiresAtUtc)}'
            : '${st.sessionName} · 等待远端服务监听端口',
        style: TextStyle(
          fontSize: 13,
          color: listening ? c.textSecondary : c.warning,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'ON',
            style: TextStyle(fontSize: 12, color: c.success),
          ),
          const SizedBox(width: 4),
          Switch(
            value: true,
            activeThumbColor: c.success,
            onChanged: screen._busy ? null : (_) => screen._stop(st),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, color: c.textSecondary),
            color: c.surfaceElevated,
            onSelected: (action) {
              switch (action) {
                case 'copy':
                  screen._copyUrl(t);
                case 'delete':
                  screen._confirmDelete(st);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('复制地址')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }
}

/// 新建规则弹层（design/06 §5）。后端 create 仅接受端口，
/// 名称/远端地址仅作表单展示，端口取本地端口值。
class _CreateSheet extends StatefulWidget {
  const _CreateSheet({required this.onSubmit});

  final ValueChanged<int> onSubmit;

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  final _nameController = TextEditingController();
  final _localPortController = TextEditingController();
  final _remoteHostController = TextEditingController(text: '127.0.0.1');
  final _remotePortController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _localPortController.dispose();
    _remoteHostController.dispose();
    _remotePortController.dispose();
    super.dispose();
  }

  void _submit() {
    final port = int.tryParse(_localPortController.text.trim());
    if (port == null || port <= 0 || port > 65535) return;
    widget.onSubmit(port);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('新建转发规则'),
          _field('名称（可选）', _nameController, keyboardType: TextInputType.text),
          _field('本地端口', _localPortController,
              keyboardType: TextInputType.number),
          _field('远端地址', _remoteHostController,
              keyboardType: TextInputType.url),
          _field('远端端口', _remotePortController,
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final remote = int.tryParse(v);
                if (remote != null &&
                    remote > 0 &&
                    _localPortController.text.isEmpty) {
                  _localPortController.text = '$remote';
                }
              }),
          const SizedBox(height: 24),
          PrimaryButton(
            label: '创建并启动',
            onPressed: _localPortController.text.isEmpty ? null : _submit,
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    required TextInputType keyboardType,
    ValueChanged<String>? onChanged,
  }) {
    final c = colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 14, color: c.textSecondary)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            onChanged: onChanged,
            style: TextStyle(color: c.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: c.surfaceElevated,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: c.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: c.divider),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtExpire(DateTime utc) {
  final local = utc.toLocal();
  return '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
