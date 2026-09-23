import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/error_text.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../../shared/widgets/states.dart';
import '../data/tunnel_repository.dart';

/// 端口转发（对齐 MAUI PortForwardingModal）：创建 / 列表 / 复制链接 / 外链打开 / 吊销。
/// 错误（端口未监听 502、配额 429、转发关闭 503 等）原样透出，不做兜底。
class PortForwardingSheet extends ConsumerStatefulWidget {
  const PortForwardingSheet({super.key, required this.sessionId});

  final String sessionId;

  static Future<void> show(BuildContext context, {required String sessionId}) {
    return showCortermSheet(
      context: context,
      builder: (_) => PortForwardingSheet(sessionId: sessionId),
    );
  }

  @override
  ConsumerState<PortForwardingSheet> createState() => _PortForwardingSheetState();
}

class _PortForwardingSheetState extends ConsumerState<PortForwardingSheet> {
  final _port = TextEditingController();
  List<TunnelSummary>? _tunnels;
  String? _error;
  bool _creating = false;
  bool _revokingId = false;
  String? _revoking;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final list = await ref.read(tunnelRepositoryProvider).list(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _tunnels = list;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorText(e, AppLocalizations.of(context)!));
    }
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context)!;
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = l10n.tunnelInvalidPort);
      return;
    }
    setState(() {
      _error = null;
      _creating = true;
    });
    try {
      final tunnel = await ref
          .read(tunnelRepositoryProvider)
          .create(sessionId: widget.sessionId, port: port);
      _port.clear();
      await _refresh();
      // 创建响应里才带 secret 的完整 URL；直接给用户复制入口。
      await Clipboard.setData(ClipboardData(text: tunnel.url));
      if (!mounted) return;
      setState(() => _creating = false);
      // 端口未监听也允许创建：worker 侧会等端口就绪，这里提示用户先起服务。
      showAppToast(
        context,
        tunnel.portOpen ? l10n.copied : l10n.tunnelPortPending,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorText(e, l10n);
        _creating = false;
      });
    }
  }

  Future<void> _revoke(TunnelSummary tunnel) async {
    setState(() {
      _error = null;
      _revokingId = true;
      _revoking = tunnel.tunnelId;
    });
    try {
      await ref.read(tunnelRepositoryProvider).revoke(tunnel.tunnelId);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorText(e, AppLocalizations.of(context)!));
    } finally {
      if (mounted) {
        setState(() {
          _revokingId = false;
          _revoking = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.tunnelTitle,
              style: theme.textTheme.large.copyWith(color: scheme.foreground),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: theme.textTheme.small.copyWith(color: scheme.destructive),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ShadInputFormField(
                    controller: _port,
                    label: Text(l10n.tunnelPortLabel),
                    placeholder: Text(l10n.tunnelPortPlaceholder),
                    keyboardType: TextInputType.number,
                    enabled: !_creating,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: ShadButton(
                    enabled: !_creating,
                    onPressed: _create,
                    child: Text(_creating ? l10n.creating : l10n.create),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_tunnels == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: ShadProgress(value: null),
                  ),
                ),
              )
            else if (_tunnels!.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.tunnelEmpty,
                  style: theme.textTheme.small.copyWith(color: scheme.mutedForeground),
                ),
              )
            else
              for (final tunnel in _tunnels!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  // 左滑删除：露出红色删除区，松手触发撤销（与 Revoke 按钮同流程）。
                  child: Dismissible(
                    key: ValueKey(tunnel.tunnelId),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: scheme.destructive,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(LucideIcons.trash2,
                          color: scheme.destructiveForeground),
                    ),
                    confirmDismiss: (_) async {
                      await _revoke(tunnel);
                      return false; // 行的移除由 _refresh 按服务端状态驱动
                    },
                    child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: scheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${l10n.tunnelPortLabel}: ${tunnel.port}',
                          style: theme.textTheme.small.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.tunnelExpires(_fmt(tunnel.expiresAtUtc)),
                          style: theme.textTheme.muted
                              .copyWith(color: scheme.mutedForeground),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ShadButton.secondary(
                              size: ShadButtonSize.sm,
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: tunnel.url));
                                showAppToast(context, l10n.copied);
                              },
                              child: Text(l10n.tunnelCopyLink),
                            ),
                            const SizedBox(width: 8),
                            ShadButton.secondary(
                              size: ShadButtonSize.sm,
                              onPressed: () => launchUrl(
                                Uri.parse(tunnel.url),
                                mode: LaunchMode.externalApplication,
                              ),
                              child: Text(l10n.tunnelOpen),
                            ),
                            const SizedBox(width: 8),
                            ShadButton.outline(
                              size: ShadButtonSize.sm,
                              enabled: !_revokingId,
                              onPressed: () => _revoke(tunnel),
                              child: Text(
                                _revoking == tunnel.tunnelId
                                    ? l10n.loading
                                    : l10n.tunnelRevoke,
                                style: TextStyle(color: scheme.destructive),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime t) {
    final local = t.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
