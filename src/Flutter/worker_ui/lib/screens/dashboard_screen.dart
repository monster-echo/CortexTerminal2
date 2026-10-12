import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_scope.dart';
import '../core/models.dart';
import '../core/self_updater.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/error_banner.dart';
import '../widgets/list_group.dart';
import '../widgets/states.dart';
/// 概览面板（Tailscale 式单列）：
/// hero 连接状态 → 我的计算机 → 此设备 → 功能入口。
/// 版本/PID 等运维指标不再是首屏主角，收进「此设备」与子页。
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WindowListener {
  // 持有数据而非 Future：刷新时旧内容保持显示，新数据回来后原地替换，
  // 不会像 FutureBuilder 换 future 那样整页闪 spinner。
  Status? _status;
  String? _error;
  bool _loading = true;
  bool _restarting = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 首次挂载后立即拉取；window focus / 子页返回触发的后续刷新走 _reload。
    _reload();
  }

  // 面板常驻（关闭只是收进托盘），无自绘刷新按钮：
  // 窗口每次回到前台自动重拉状态。
  @override
  void onWindowFocus() {
    _reload();
  }

  Future<void> _reload() async {
    try {
      final s = await AppScope.of(context).service.status();
      if (!mounted) return;
      setState(() {
        _status = s;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // 拉取失败时保留旧内容，只弹错误条，不白屏。
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 推子页；返回面板后静默重拉（登录/登出/更新等可能改了本机状态）。
  Future<void> _go(BuildContext context, String location) async {
    await context.push(location);
    _reload();
  }

  /// 服务离线时的一键恢复：corterm restart → 重拉状态。
  Future<void> _restartService() async {
    setState(() => _restarting = true);
    try {
      await AppScope.of(context).service.service('restart');
      if (!mounted) return;
      showAppToast(context, AppStrings.t(context, 'panel.restarted'));
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, e.toString(), destructive: true);
    }
    setState(() => _restarting = false);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: SmallSpinner()))
          else ...[
            ErrorBanner(message: _error),
            if (status != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  _hero(context, status),
                  if (status.authenticated && status.workers.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _computersSection(context, status),
                  ],
                  const SizedBox(height: 24),
                  _deviceSection(context, status),
                  const SizedBox(height: 24),
                  _entriesSection(context, status),
                ],
              ),
          ],
        ],
      ),
    );
  }

  // 黑白反色主按钮（设计规范：主操作不用品牌色），32dp 高、内容自适应。
  Widget _inverseButton(
    BuildContext context, {
    required String label,
    VoidCallback? onPressed,
    bool busy = false,
  }) {
    final scheme = ShadTheme.of(context).colorScheme;
    return ShadButton(
      height: 32,
      backgroundColor: scheme.foreground,
      foregroundColor: scheme.background,
      onPressed: onPressed,
      enabled: onPressed != null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: scheme.background),
            ),
            const SizedBox(width: 6),
          ],
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  // ── Hero：连接状态，全屏唯一视觉主角 ──
  Widget _hero(BuildContext context, Status s) {
    final t = AppStrings.t;
    final scheme = ShadTheme.of(context).colorScheme;
    final selfOnline = s.workers
        .where((w) => w.workerId == s.workerId)
        .any((w) => w.isOnline);
    final connected = s.authenticated && selfOnline;
    final serviceOffline = s.authenticated && !selfOnline;
    final title = connected
        ? 'panel.connected'
        : serviceOffline
            ? 'panel.serviceOffline'
            : 'panel.disconnected';
    final hint = connected
        ? 'panel.connectedHint'
        : serviceOffline
            ? 'panel.serviceOfflineHint'
            : 'panel.disconnectedHint';
    // 离线用警示黄（状态色，与品牌色分开）；未连接才是灰。
    final color = connected
        ? scheme.tertiary
        : serviceOffline
            ? scheme.warning
            : scheme.mutedForeground;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态行：圆点 + 标题 + 行尾操作（重启/登录），一行说完状态与动作。
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                t(context, title),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.foreground),
              ),
              const Spacer(),
              if (serviceOffline)
                _inverseButton(
                  context,
                  label: t(context, 'panel.restartService'),
                  busy: _restarting,
                  onPressed: _restarting ? null : _restartService,
                ),
              if (!s.authenticated)
                _inverseButton(
                  context,
                  label: t(context, 'panel.loginConnect'),
                  onPressed: () => _go(context, '/auth'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            t(context, hint),
            style: TextStyle(fontSize: 13, color: scheme.mutedForeground),
          ),
          if (s.authenticated && s.user != null) ...[
            const SizedBox(height: 12),
            // 账号行：avatar + 用户名，点击进认证页（登出 / 切换账号）。
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _go(context, '/auth'),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      s.user!.characters.first.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.user!,
                      style: TextStyle(fontSize: 13, color: scheme.mutedForeground),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(LucideIcons.chevronRight, size: 14, color: scheme.mutedForeground),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 我的计算机：账号下其他在线设备 ──
  Widget _computersSection(BuildContext context, Status s) {
    final t = AppStrings.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, t(context, 'panel.computers')),
        const SizedBox(height: 8),
        AppGroupCard(
          children: [
            for (var i = 0; i < s.workers.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              AppRow(
                leadingWidget: _statusDot(context, s.workers[i].isOnline),
                label: s.workers[i].displayName,
                value: t(context, s.workers[i].isOnline ? 'panel.online' : 'panel.offline'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ── 此设备：本机标识与连接信息，只读键值行 ──
  Widget _deviceSection(BuildContext context, Status s) {
    final t = AppStrings.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, t(context, 'panel.thisDevice')),
        const SizedBox(height: 8),
        AppGroupCard(
          children: [
            AppRow(label: t(context, 'panel.deviceId'), value: s.workerId),
            const Divider(height: 1),
            AppRow(
              label: t(context, 'panel.serviceVersion'),
              value: s.version,
              chevron: s.updateAvailable,
              trailing: s.updateAvailable ? _updateBadge(context) : null,
              onTap: s.updateAvailable ? () => _go(context, '/update') : null,
            ),
            const Divider(height: 1),
            AppRow(label: t(context, 'panel.gateway'), value: s.gateway),
            const Divider(height: 1),
            AppRow(label: t(context, 'panel.uptime'), value: s.uptime),
          ],
        ),
      ],
    );
  }

  // ── 功能入口：会话 / Agent 工具 / 诊断 / 设置 / 关于 ──
  Widget _entriesSection(BuildContext context, Status s) {
    final t = AppStrings.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppGroupCard(
          children: [
            AppRow(
              icon: LucideIcons.terminal,
              label: t(context, 'nav.sessions'),
              chevron: true,
              onTap: () => _go(context, '/sessions'),
            ),
            const Divider(height: 1),
            AppRow(
              icon: LucideIcons.cpu,
              label: t(context, 'nav.agentTools'),
              chevron: true,
              onTap: () => _go(context, '/agent-tools'),
            ),
            const Divider(height: 1),
            AppRow(
              icon: LucideIcons.download,
              label: t(context, 'nav.update'),
              chevron: true,
              trailing: s.updateAvailable ? _updateBadge(context) : null,
              onTap: () => _go(context, '/update'),
            ),
            const Divider(height: 1),
            AppRow(
              icon: LucideIcons.shieldCheck,
              label: t(context, 'nav.doctor'),
              chevron: true,
              onTap: () => _go(context, '/doctor'),
            ),
            const Divider(height: 1),
            AppRow(
              icon: LucideIcons.settings,
              label: t(context, 'nav.settings'),
              chevron: true,
              onTap: () => _go(context, '/settings'),
            ),
            const Divider(height: 1),
            AppRow(
              icon: LucideIcons.info,
              label: t(context, 'about.title'),
              value: 'v$appVersion',
              chevron: true,
              onTap: () => _go(context, '/about'),
            ),
          ],
        ),
      ],
    );
  }

  // 分区小标题：12sp/500/muted，安静地给分组命名。
  Widget _sectionLabel(BuildContext context, String text) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: scheme.mutedForeground,
      ),
    );
  }

  Widget _statusDot(BuildContext context, bool online) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: online ? scheme.tertiary : scheme.mutedForeground,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _updateBadge(BuildContext context) {
    final t = AppStrings.t;
    final scheme = ShadTheme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        t(context, 'panel.updateAvailable'),
        style: TextStyle(fontSize: 11, color: scheme.primary),
      ),
    );
  }
}
