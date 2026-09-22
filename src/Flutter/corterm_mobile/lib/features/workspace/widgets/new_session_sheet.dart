import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../../shared/widgets/states.dart';
import '../../sessions/data/sessions_providers.dart';
import '../../sessions/data/session_repository.dart';

/// New Session 流程——与 MAUI CreateSessionModal 逐项对齐（旧用户习惯不变）：
/// 顶部「取消 / 创建会话 / 创建(创建中…)」，内容为在线 worker 单选列表
/// （默认选中第一个在线 worker），创建按钮仅在未创建中时可用。
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
  return showCortermSheet(
    context: context,
    minHeightFactor: 2 / 3, // 固定 2/3 屏（上限同值）：与 Material sheet 惯例一致。
    maxHeightFactor: 2 / 3,
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

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部栏：取消 / 创建会话 / 创建（对齐 MAUI IonToolbar 布局）。
          Row(
            children: [
              ShadButton.ghost(
                onPressed: _creating ? null : () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              Expanded(
                child: Text(
                  l10n.createSession,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.small.copyWith(
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
          // Worker 不再让用户挑（默认第一个在线，用户无需理解选择成本）。
          // 仅在线 worker 列表为空时给出不可创建的原因。
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
              return const SizedBox.shrink();
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
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

