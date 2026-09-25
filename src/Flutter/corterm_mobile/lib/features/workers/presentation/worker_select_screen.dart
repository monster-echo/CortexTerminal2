import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../core/models/worker.dart';
import '../../../shared/widgets/corterm_ui.dart';
import '../../sessions/data/sessions_providers.dart';

/// 电脑选择页（design/02：选择类操作用独立页面，与文件夹选择一致）。
/// 点选一台电脑后 pop 返回 [WorkerSummary]。
class WorkerSelectScreen extends ConsumerWidget {
  const WorkerSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = colorsOf(context);
    final workersAsync = ref.watch(workersProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('选择电脑'),
      ),
      body: switch (workersAsync) {
        AsyncLoading() => const Center(child: CircularProgressIndicator()),
        AsyncError(:final error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('$error',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.danger)),
            ),
          ),
        AsyncValue(:final value) => (value ?? const []).isEmpty
            ? const EmptyState(
                icon: Icons.computer_outlined, message: '还没有配对电脑')
            : ListView(
                children: [
                  for (final w in value ?? const <WorkerSummary>[])
                    ListRow(
                      title: w.displayName,
                      subtitle:
                          '${w.isOnline ? '在线' : '离线'} · ${w.hostname ?? ''}',
                      leading: const Icon(Icons.computer_outlined),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, w),
                    ),
                ],
              ),
      },
    );
  }
}
