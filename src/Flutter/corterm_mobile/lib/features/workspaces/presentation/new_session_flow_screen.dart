import '../../../shared/layout/adaptive_page_scaffold.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../sessions/data/session_repository.dart';
import '../../sessions/data/sessions_providers.dart';
import '../data/workspace_providers.dart';

/// Creates immediately in the first computer's first workspace.
class NewSessionFlowScreen extends ConsumerStatefulWidget {
  const NewSessionFlowScreen({super.key, this.lockWorkspaceId});
  final String? lockWorkspaceId;

  @override
  ConsumerState<NewSessionFlowScreen> createState() =>
      _NewSessionFlowScreenState();
}

class _NewSessionFlowScreenState extends ConsumerState<NewSessionFlowScreen> {
  bool _creating = false;
  String? _error;
  String? _solutionRoute;
  String? _solutionLabel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _create());
  }

  Future<void> _create() async {
    if (_creating || !mounted) return;
    setState(() {
      _creating = true;
      _error = null;
      _solutionRoute = null;
      _solutionLabel = null;
    });
    try {
      final workers = await ref.read(workersProvider.future);
      if (!mounted) return;
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      if (workers.isEmpty) {
        _solutionRoute = '/computers/new';
        _solutionLabel = zh ? '连接电脑' : 'Connect a computer';
        throw StateError(zh ? '请先连接一台电脑。' : 'Connect a computer first.');
      }
      final workspaces = await ref.read(workspacesProvider.future);
      if (!mounted) return;
      final workspace = widget.lockWorkspaceId != null
          ? workspaces
                .where((w) => w.workspaceId == widget.lockWorkspaceId)
                .firstOrNull
          : workspaces
                .where((w) => w.workerId == workers.first.workerId)
                .firstOrNull;
      if (workspace == null) {
        final missingSelection = widget.lockWorkspaceId != null;
        _solutionRoute = missingSelection ? '/home' : '/workspaces/new';
        _solutionLabel = missingSelection
            ? (zh ? '选择工作区' : 'Choose a workspace')
            : (zh ? '新建工作区' : 'Create a workspace');
        throw StateError(
          missingSelection
              ? (zh
                    ? '这个工作区已不可用，请选择其他工作区。'
                    : 'This workspace is no longer available. Choose another workspace.')
              : (zh
                    ? '请先为这台电脑添加工作区。'
                    : 'Add a workspace to this computer first.'),
        );
      }
      final worker = workers
          .where((w) => w.workerId == workspace.workerId)
          .firstOrNull;
      if (worker == null || !worker.isOnline) {
        _solutionRoute = worker == null
            ? '/computers'
            : '/computers/${worker.workerId}';
        _solutionLabel = zh ? '查看电脑' : 'View computer';
        throw StateError(
          zh
              ? '电脑当前离线，请启动电脑上的云枢终端后重试。'
              : 'The computer is offline. Start Corterm on it and retry.',
        );
      }
      final session = await ref
          .read(sessionRepositoryProvider)
          .create(
            columns: 80,
            rows: 24,
            workerId: workspace.workerId,
            workspaceId: workspace.workspaceId,
          );
      if (!mounted) return;
      ref.invalidate(sessionsProvider);
      context.pushReplacement('/sessions/${session.sessionId}');
    } catch (error) {
      if (mounted) {
        setState(() {
          _creating = false;
          _error = error is StateError ? error.message.toString() : '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AdaptivePageScaffold(
      appBar: AppBar(title: Text(l10n.newSession)),
      body: _error == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_error!),
                  const SizedBox(height: 16),
                  if (_solutionRoute != null) ...[
                    FilledButton(
                      onPressed: () => context.push(_solutionRoute!),
                      child: Text(_solutionLabel!),
                    ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton(
                    onPressed: () {
                      ref.invalidate(workersProvider);
                      ref.invalidate(workspacesProvider);
                      _create();
                    },
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            ),
    );
  }
}
