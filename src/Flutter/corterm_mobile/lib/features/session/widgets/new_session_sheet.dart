import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/connection_status_dot.dart';
import '../../../shared/widgets/list_group.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../../shared/widgets/states.dart';
import '../../sessions/data/sessions_providers.dart';
import '../../sessions/data/session_repository.dart';
import 'session_status.dart';

/// New Session 流程——与 MAUI CreateSessionModal 逐项对齐（旧用户习惯不变）：
/// 顶部「创建会话 / 创建(创建中…)」，下滑 / 点遮罩关闭；内容为
/// 在线 worker 单选列表（默认选中第一个在线 worker），创建按钮仅在未创建中时可用。
/// 终端尺寸按 MAUI 公式由视口推导：fontSize 14，cols=w/(14*0.602)，rows=(h-44)/(14*1.2)。
/// 成功后关闭并回调；失败弹 danger toast。
Future<void> showNewSessionSheet(
  BuildContext context, {
  required void Function(String sessionId) onCreated,
}) async {
  // MAUI useCreateSession.openModal：无在线 worker 时不打开弹窗。
  final container = ProviderScope.containerOf(context);
  final workers = container.read(workersProvider).value ?? const [];
  final hasOnline = workers.any((w) => w.isOnline);
  if (workers.isNotEmpty && !hasOnline) {
    if (context.mounted) {
      showAppToast(
        context,
        AppLocalizations.of(context)!.noWorkers,
        destructive: true,
      );
    }
    return;
  }
  if (!context.mounted) return;
  // 内容自适应高度：内容只有一行工具栏（+ loading/错误提示），撑满 2/3 屏
  // 只会留大片空白。下滑 sheet 即可关闭。
  return showCortermSheet(
    context: context,
    builder: (_) => NewSessionSheet(onCreated: onCreated),
  );
}

class NewSessionSheet extends ConsumerStatefulWidget {
  const NewSessionSheet({super.key, required this.onCreated});

  final void Function(String sessionId) onCreated;

  @override
  ConsumerState<NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends ConsumerState<NewSessionSheet> {
  String? _selectedWorkerId;
  bool _creating = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final workersAsync = ref.watch(workersProvider);
    final online =
        (workersAsync.value ?? const []).where((w) => w.isOnline).toList();
    // MAUI：默认选中第一个在线 worker。
    if (_selectedWorkerId == null && online.isNotEmpty) {
      _selectedWorkerId = online.first.workerId;
    }

    // 边距 / 底部 safe area 由 showCortermSheet 统一提供。
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
          // 顶部栏：标题 + 创建。关闭走下滑 / 点遮罩。
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.createSession,
                  textAlign: TextAlign.left,
                  style: theme.textTheme.large.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.foreground,
                  ),
                ),
              ),
              ShadButton(
                // MAUI：创建按钮在创建期间禁用并显示「创建中…」。
                enabled: !_creating && _selectedWorkerId != null,
                onPressed: _create,
                child: Text(_creating ? l10n.creating : l10n.create),
              ),
            ],
          ),
          const SizedBox(height: 8),
          workersAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 120, child: ShadProgress(value: null)),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.noWorkers,
                style: theme.textTheme.small.copyWith(color: scheme.destructive),
              ),
            ),
            data: (list) {
              if (online.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    l10n.noWorkers,
                    style: theme.textTheme.small.copyWith(color: scheme.foreground),
                  ),
                );
              }
              // 在线 worker 单选列表：默认选中第一个（MAUI 惯例），
              // 多个在线时让用户指定落到哪台机器上。
              // 选中态用行尾勾号（iOS 风格单选）——不用 ShadRadioGroup/Wrap，
              // 它们嵌在 sheet 滚动上下文里是布局异常重灾区。
              return AppGroupCard(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final w in online)
                    AppRow(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      leadingWidget: ConnectionStatusDot(
                        color: workerDotColor(scheme, w),
                        size: 10,
                        pulse: w.isOnline,
                      ),
                      label: w.displayName,
                      onTap: () =>
                          setState(() => _selectedWorkerId = w.workerId),
                      trailing: _selectedWorkerId == w.workerId
                          ? Icon(LucideIcons.check, size: 18, color: scheme.primary)
                          : null,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      );
  }

  /// MAUI useCreateSession.createSession：视口推导终端尺寸后创建。
  Future<void> _create() async {
    final workerId = _selectedWorkerId;
    if (workerId == null || _creating) return;
    setState(() => _creating = true);
    try {
      const fontSize = 14.0;
      const charWidth = fontSize * 0.602;
      const charHeight = fontSize * 1.2;
      final size = MediaQuery.sizeOf(context);
      final cols = (size.width / charWidth).floor();
      final rows = ((size.height - 44) / charHeight).floor();

      final session = await ref.read(sessionRepositoryProvider).create(
            columns: cols,
            rows: rows,
            workerId: workerId,
          );
      ref.invalidate(sessionsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onCreated(session.sessionId);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '$e', destructive: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }
}

