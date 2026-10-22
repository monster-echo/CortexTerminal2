import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_scope.dart';
import '../core/models.dart';
import '../core/self_updater.dart';
import '../core/worker_process_controller.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/error_banner.dart';
import '../widgets/list_group.dart';
import '../widgets/states.dart';

/// 紧凑桌面面板：连接与账号 → 折叠设备列表 → 本机信息 → 工具。
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
  Timer? _pollTimer;
  bool _computersExpanded = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // 状态是异步收敛的（装 worker → spawn → 连网关），仅靠窗口聚焦刷新会有
    // "实际在线但面板还挂着旧快照"的间隙：30s 轮询兜底（同托盘刷新节奏），
    // 控制器生命周期变化（启动中/退避重启）即时触发。
    WorkerProcessController.instance.runState.addListener(_onRunStateChanged);
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _reload());
  }

  void _onRunStateChanged() {
    if (mounted) _reload();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _pollTimer?.cancel();
    WorkerProcessController.instance.runState.removeListener(
      _onRunStateChanged,
    );
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

  /// 服务离线时的一键恢复：重启 worker → 重拉状态。
  /// macOS：worker 是本 App 托管的子进程，直接重启子进程（CLI 的 restart
  /// 会走 launchctl，把 LaunchAgent 又装回来）；其他平台走系统服务。
  Future<void> _restartService() async {
    setState(() => _restarting = true);
    try {
      if (Platform.isMacOS) {
        await WorkerProcessController.instance.restart();
      } else {
        final result = await AppScope.of(context).service.service('restart');
        if (!result.ok) {
          throw Exception(result.error ?? result.message);
        }
      }
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
        padding: const EdgeInsets.all(20),
        children: [
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: SmallSpinner(),
              ),
            )
          else ...[
            ErrorBanner(message: _error),
            if (status != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  _sectionLabel(
                    context,
                    AppStrings.t(context, 'panel.connection'),
                  ),
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
      // 悬停保持黑白反色，不回落到主题的品牌蓝。
      hoverBackgroundColor: scheme.foreground.withValues(alpha: 0.85),
      hoverForegroundColor: scheme.background,
      onPressed: onPressed,
      enabled: onPressed != null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.background,
              ),
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
    // 已登录但网关侧还没看到本机在线：若控制器正在拉起/退避重启，是暂态，
    // 展示「启动中」而不是「服务离线」（避免首启窗口期误报故障）。
    final starting =
        s.authenticated &&
        !selfOnline &&
        WorkerProcessController.instance.runState.value !=
            WorkerRunState.stopped;
    final serviceOffline = s.authenticated && !selfOnline && !starting;
    final title = connected
        ? 'panel.connected'
        : serviceOffline
        ? 'panel.serviceOffline'
        : starting
        ? 'panel.starting'
        : 'panel.disconnected';
    final hint = connected
        ? 'panel.connectedHint'
        : serviceOffline
        ? 'panel.serviceOfflineHint'
        : starting
        ? 'panel.startingHint'
        : 'panel.disconnectedHint';
    // 离线用警示黄（状态色，与品牌色分开）；未连接才是灰；启动中是中性过渡。
    final color = connected
        ? scheme.tertiary
        : serviceOffline
        ? scheme.warning
        : starting
        ? scheme.secondary
        : scheme.mutedForeground;
    return AppGroupCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t(context, title),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t(context, hint),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              if (serviceOffline || !s.authenticated) ...[
                const SizedBox(width: 12),
                _inverseButton(
                  context,
                  label: t(
                    context,
                    serviceOffline ? 'panel.restartService' : 'auth.login',
                  ),
                  busy: _restarting,
                  onPressed: _restarting
                      ? null
                      : serviceOffline
                      ? _restartService
                      : () => _go(context, '/auth'),
                ),
              ],
            ],
          ),
        ),
        if (s.authenticated) ...[
          const Divider(height: 1),
          _accountRow(context, s.user ?? t(context, 'panel.account')),
        ],
      ],
    );
  }

  // ── 我的计算机：账号下其他在线设备 ──
  Widget _computersSection(BuildContext context, Status s) {
    final t = AppStrings.t;
    final workers = [...s.workers]
      ..sort((a, b) {
        if (a.workerId == s.workerId) return -1;
        if (b.workerId == s.workerId) return 1;
        return (b.isOnline ? 1 : 0).compareTo(a.isOnline ? 1 : 0);
      });
    final summary = t(context, 'panel.computersSummary')
        .replaceAll('{total}', '${workers.length}')
        .replaceAll('{online}', '${workers.where((w) => w.isOnline).length}');
    return AppGroupCard(
      children: [
        _compactRow(
          context,
          icon: LucideIcons.monitor,
          label: t(context, 'panel.computers'),
          value: summary,
          trailing: Icon(
            _computersExpanded
                ? LucideIcons.chevronDown
                : LucideIcons.chevronRight,
            size: 16,
            color: ShadTheme.of(context).colorScheme.mutedForeground,
          ),
          onTap: () => setState(() => _computersExpanded = !_computersExpanded),
        ),
        if (_computersExpanded)
          for (final worker in workers) ...[
            const Divider(height: 1),
            _compactRow(
              context,
              leading: _statusDot(context, worker.isOnline),
              label: worker.displayName,
              value: worker.workerId == s.workerId
                  ? '${t(context, 'panel.thisDevice')} · ${t(context, worker.isOnline ? 'panel.online' : 'panel.offline')}'
                  : t(
                      context,
                      worker.isOnline ? 'panel.online' : 'panel.offline',
                    ),
            ),
          ],
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
            _compactRow(
              context,
              label: t(context, 'panel.serviceVersion'),
              value: s.version,
              trailing: TextButton(
                onPressed: () => _go(context, '/update'),
                child: Text(
                  t(
                    context,
                    s.updateAvailable ? 'panel.upgrade' : 'nav.update',
                  ),
                ),
              ),
            ),
            if (s.updateAvailable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    s.latestWorkerVersion == null
                        ? t(context, 'panel.updateAvailable')
                        : '${t(context, 'panel.updateAvailable')} · ${s.latestWorkerVersion}',
                    style: TextStyle(
                      fontSize: 12,
                      color: ShadTheme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            const Divider(height: 1),
            _compactRow(
              context,
              label: t(context, 'panel.uptime'),
              value: s.uptime,
            ),
            const Divider(height: 1),
            _compactRow(
              context,
              label: t(context, 'panel.deviceId'),
              value: s.workerId,
            ),
          ],
        ),
      ],
    );
  }

  Widget _entriesSection(BuildContext context, Status s) {
    final t = AppStrings.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, t(context, 'panel.tools')),
        const SizedBox(height: 8),
        AppGroupCard(
          children: [
            _compactRow(
              context,
              icon: LucideIcons.cpu,
              label: t(context, 'nav.agentTools'),
              chevron: true,
              onTap: () => _go(context, '/agent-tools'),
            ),
            const Divider(height: 1),
            _compactRow(
              context,
              icon: LucideIcons.shieldCheck,
              label: t(context, 'doctor.title'),
              chevron: true,
              onTap: () => _go(context, '/doctor'),
            ),
            const Divider(height: 1),
            _compactRow(
              context,
              icon: LucideIcons.settings,
              label: t(context, 'nav.settings'),
              chevron: true,
              onTap: () => _go(context, '/settings'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _go(context, '/about'),
            child: Text(
              '${t(context, 'about.title')} · v$appVersion',
              style: TextStyle(
                fontSize: 12,
                color: ShadTheme.of(context).colorScheme.mutedForeground,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 桌面键值行；窄窗口和大字体时自动改为两行，操作始终保留空间。
  Widget _accountRow(BuildContext context, String account) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => _go(context, '/auth'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Icon(
                    LucideIcons.user,
                    size: 18,
                    color: scheme.mutedForeground,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    account,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: scheme.foreground),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  AppStrings.t(context, 'panel.manageAccount'),
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 12, color: scheme.mutedForeground),
                ),
                const SizedBox(width: 8),
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: scheme.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 桌面键值行；窄窗口和大字体时自动改为两行，操作始终保留空间。
  Widget _compactRow(
    BuildContext context, {
    required String label,
    String? value,
    IconData? icon,
    Widget? leading,
    Widget? trailing,
    bool chevron = false,
    VoidCallback? onTap,
  }) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (leading != null || icon != null) ...[
                  SizedBox(
                    width: 20,
                    child: Center(
                      child:
                          leading ??
                          Icon(icon, size: 18, color: scheme.mutedForeground),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final title = Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.foreground,
                        ),
                      );
                      if (value == null) return title;
                      final detail = Text(
                        value,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.mutedForeground,
                        ),
                      );
                      if (constraints.maxWidth < 340 ||
                          MediaQuery.textScalerOf(context).scale(13) > 18) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [title, const SizedBox(height: 4), detail],
                        );
                      }
                      return Row(
                        children: [
                          SizedBox(width: 104, child: title),
                          Expanded(child: detail),
                        ],
                      );
                    },
                  ),
                ),
                if (trailing != null || chevron) ...[
                  const SizedBox(width: 8),
                  trailing ??
                      Icon(
                        LucideIcons.chevronRight,
                        size: 16,
                        color: scheme.mutedForeground,
                      ),
                ],
              ],
            ),
          ),
        ),
      ),
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
}
