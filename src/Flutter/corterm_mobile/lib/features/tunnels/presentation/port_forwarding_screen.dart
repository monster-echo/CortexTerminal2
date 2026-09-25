import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../shared/widgets/corterm_ui.dart';
import '../../../shared/widgets/states.dart' show ErrorState, showAppToast;
import '../../tunnels/data/tunnel_repository.dart';

/// 端口转发（Dark Tool Context，design/06）：规则归属 Workspace，
/// 开 = 存在运行中的转发，关 = revoke（删除规则）。
class PortForwardingScreen extends ConsumerStatefulWidget {
  const PortForwardingScreen({super.key, required this.workspaceId});

  final String workspaceId;

  @override
  ConsumerState<PortForwardingScreen> createState() =>
      _PortForwardingScreenState();
}

class _PortForwardingScreenState extends ConsumerState<PortForwardingScreen> {
  late Future<List<TunnelSummary>> _future = _load();

  bool _busy = false;

  Future<List<TunnelSummary>> _load() =>
      ref.read(tunnelRepositoryProvider).list(widget.workspaceId);

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _create({
    String? name,
    required int localPort,
    required String remoteAddress,
    required int remotePort,
  }) async {
    setState(() => _busy = true);
    try {
      await ref.read(tunnelRepositoryProvider).create(
            workspaceId: widget.workspaceId,
            name: name,
            localPort: localPort,
            remoteAddress: remoteAddress,
            remotePort: remotePort,
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

  Future<void> _edit(
    TunnelSummary t, {
    String? name,
    required int localPort,
    required String remoteAddress,
    required int remotePort,
  }) async {
    setState(() => _busy = true);
    try {
      await ref.read(tunnelRepositoryProvider).update(
            workspaceId: widget.workspaceId,
            tunnelId: t.tunnelId,
            name: name,
            localPort: localPort,
            remoteAddress: remoteAddress,
            remotePort: remotePort,
          );
      if (!mounted) return;
      showAppToast(context, '转发已更新');
      await _refresh();
    } catch (e) {
      if (mounted) showAppToast(context, '更新失败：$e', destructive: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop(TunnelSummary t) async {
    setState(() => _busy = true);
    try {
      await ref.read(tunnelRepositoryProvider).revoke(t.tunnelId);
      if (!mounted) return;
      showAppToast(context, '转发已停止');
      await _refresh();
    } catch (e) {
      if (mounted) showAppToast(context, '停止失败：$e', destructive: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _confirmDelete(TunnelSummary t) {
    final c = colorsOf(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: c.surfaceElevated,
        title: Text('删除转发规则', style: TextStyle(color: c.textPrimary)),
        content: Text(
          '${t.name ?? '规则'}（${t.localPort} → ${t.remoteAddress}:${t.remotePort}）将被删除，此操作不可撤销。',
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
              _stop(t);
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

  void _showRuleSheet({TunnelSummary? existing}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorsOf(context).surface,
      builder: (_) => _RuleSheet(
        existing: existing,
        onSubmit: (name, localPort, remoteAddress, remotePort) {
          Navigator.of(context).pop();
          if (existing != null) {
            _edit(existing,
                name: name,
                localPort: localPort,
                remoteAddress: remoteAddress,
                remotePort: remotePort);
          } else {
            _create(
                name: name,
                localPort: localPort,
                remoteAddress: remoteAddress,
                remotePort: remotePort);
          }
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
          return Scaffold(
            backgroundColor: c.background,
            appBar: AppBar(
              title: const Text('端口转发'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: '新建转发规则',
                  onPressed: _busy ? null : _showRuleSheet,
                ),
              ],
            ),
            body: FutureBuilder<List<TunnelSummary>>(
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
                  itemBuilder: (context, i) => _TunnelTile(
                    tunnel: tunnels[i],
                    screen: this,
                  ),
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
  const _TunnelTile({required this.tunnel, required this.screen});

  final TunnelSummary tunnel;
  final _PortForwardingScreenState screen;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final t = tunnel;
    return ListTile(
      title: Text(
        '${t.name ?? '规则'} ${t.localPort} → ${t.remoteAddress}:${t.remotePort}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 16, color: c.textPrimary),
      ),
      subtitle: Text(
        t.portOpen
            ? '运行中 · 到期 ${_fmtExpire(t.expiresAtUtc)}'
            : '等待远端服务监听 ${t.remoteAddress}:${t.remotePort}',
        style: TextStyle(
          fontSize: 13,
          color: t.portOpen ? c.textSecondary : c.warning,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t.running ? 'ON' : 'OFF',
            style: TextStyle(
                fontSize: 12, color: t.running ? c.success : c.textSecondary),
          ),
          const SizedBox(width: 4),
          Switch(
            value: t.running,
            activeThumbColor: c.success,
            onChanged: screen._busy ? null : (_) => screen._stop(t),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, color: c.textSecondary),
            color: c.surfaceElevated,
            onSelected: (action) {
              switch (action) {
                case 'edit':
                  screen._showRuleSheet(existing: t);
                case 'copy':
                  screen._copyUrl(t);
                case 'delete':
                  screen._confirmDelete(t);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('编辑')),
              PopupMenuItem(value: 'copy', child: Text('复制地址')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }
}

/// 新建/编辑规则弹层（design/06 §5）。[existing] 非 null 时为编辑（提交走 PATCH）。
class _RuleSheet extends StatefulWidget {
  const _RuleSheet({required this.onSubmit, this.existing});

  final TunnelSummary? existing;
  final void Function(
          String? name, int localPort, String remoteAddress, int remotePort)
      onSubmit;

  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  late final _nameController =
      TextEditingController(text: widget.existing?.name ?? '');
  late final _localPortController = TextEditingController(
      text: widget.existing == null ? '' : '${widget.existing!.localPort}');
  late final _remoteHostController =
      TextEditingController(text: widget.existing?.remoteAddress ?? '127.0.0.1');
  late final _remotePortController = TextEditingController(
      text: widget.existing == null ? '' : '${widget.existing!.remotePort}');

  @override
  void dispose() {
    _nameController.dispose();
    _localPortController.dispose();
    _remoteHostController.dispose();
    _remotePortController.dispose();
    super.dispose();
  }

  bool _validPort(String text) {
    final port = int.tryParse(text.trim());
    return port != null && port > 0 && port <= 65535;
  }

  void _submit() {
    if (!_validPort(_localPortController.text) ||
        !_validPort(_remotePortController.text)) {
      return;
    }
    final remoteHost = _remoteHostController.text.trim();
    widget.onSubmit(
      _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
      int.parse(_localPortController.text.trim()),
      remoteHost.isEmpty ? '127.0.0.1' : remoteHost,
      int.parse(_remotePortController.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        _validPort(_localPortController.text) && _validPort(_remotePortController.text);
    // Modal 路由在 Navigator 根上，显式包 Dark Theme 保证弹层对比度。
    return Theme(
      data: cortermDarkToolTheme(),
      child: Builder(builder: (context) {
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
          SectionHeader(widget.existing == null ? '新建转发规则' : '编辑转发规则'),
          _field(context, '名称（可选）', _nameController, keyboardType: TextInputType.text),
          _field(context, '本地端口', _localPortController,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {})),
          _field(context, '远端地址', _remoteHostController,
              keyboardType: TextInputType.url),
          _field(context, '远端端口', _remotePortController,
              keyboardType: TextInputType.number, onChanged: (v) {
            setState(() {});
            // 输入远端端口后，本地端口默认同值，用户可修改。
            final remote = int.tryParse(v);
            if (remote != null &&
                remote > 0 &&
                _localPortController.text.isEmpty) {
              _localPortController.text = '$remote';
            }
          }),
          const SizedBox(height: 24),
          PrimaryButton(
            label: widget.existing == null ? '创建并启动' : '保存',
            onPressed: canSubmit ? _submit : null,
          ),
        ],
      ),
          );
        }),
      );
  }

  Widget _field(
    BuildContext context,
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
