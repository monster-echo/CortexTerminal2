import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/models/workspace.dart';
import '../../../shared/widgets/corterm_ui.dart';
import '../../sessions/data/session_repository.dart';
import '../../sessions/data/sessions_providers.dart';
import '../data/workspace_providers.dart';

/// 新建 Session（design/02 §5）：无类型选择；锁定工作区时直接可建，否则选电脑 → 工作区。
class NewSessionFlowScreen extends ConsumerStatefulWidget {
  const NewSessionFlowScreen({super.key, this.lockWorkspaceId});

  final String? lockWorkspaceId;

  @override
  ConsumerState<NewSessionFlowScreen> createState() =>
      _NewSessionFlowScreenState();
}

class _NewSessionFlowScreenState extends ConsumerState<NewSessionFlowScreen> {
  String? _workerId;
  String? _workspaceId;
  String? _error;
  bool _creating = false;

  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _workspaceId = widget.lockWorkspaceId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create(Workspace workspace) async {
    if (_creating) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final repo = ref.read(sessionRepositoryProvider);
      final s = await repo.create(
        columns: 80,
        rows: 24,
        workerId: workspace.workerId,
        workspaceId: workspace.workspaceId,
        name: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
      );
      if (!mounted) return;
      ref.invalidate(sessionsProvider);
      if (mounted) context.pushReplacement('/sessions/${s.sessionId}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _creating = false;
      });
    }
  }

  /// Create a workspace, then return with it selected for confirmation.
  Future<void> _newWorkspace() async {
    final ws = await context.push<Workspace>(
      '/workspaces/new?workerId=$_workerId&returnResult=1',
    );
    if (ws == null || !mounted) return;
    setState(() => _workspaceId = ws.workspaceId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    final l10n = AppLocalizations.of(context)!;
    final workspacesAsync = ref.watch(workspacesProvider);
    final workspaces = workspacesAsync.asData?.value ?? const <Workspace>[];
    final selectedWorkspace = workspaces
        .where((w) => w.workspaceId == _workspaceId)
        .firstOrNull;
    final workersAsync = ref.watch(workersProvider);
    final workers = workersAsync.asData?.value ?? const [];
    final isLocked = widget.lockWorkspaceId != null;
    final selectedWorkerId = selectedWorkspace?.workerId ?? _workerId;
    final availableWorkspaces =
        workspaces.where((w) => w.workerId == selectedWorkerId).toList()
          ..sort((a, b) {
            if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
            return a.displayName.compareTo(b.displayName);
          });

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(l10n.newSession),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          SectionHeader(l10n.computersTitle),
          if (workersAsync.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (workersAsync.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${workersAsync.error}',
                    style: TextStyle(fontSize: 14, color: colors.danger),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(workersProvider),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            )
          else if (isLocked && selectedWorkspace != null)
            ListRow(
              title:
                  workers
                      .where((w) => w.workerId == selectedWorkspace.workerId)
                      .map((w) => w.displayName)
                      .firstOrNull ??
                  selectedWorkspace.workerId,
              leading: const Icon(Icons.computer),
            )
          else if (workers.where((w) => w.isOnline).isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: EmptyState(icon: Icons.computer_outlined, message: l10n.noWorkers),
            )
          else
            for (final w
                in workers.toList()..sort((a, b) {
                  if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
                  return a.displayName.compareTo(b.displayName);
                }))
              ListRow(
                title: w.displayName,
                subtitle:
                    w.hostname == null ||
                        w.hostname!.isEmpty ||
                        w.hostname == w.displayName
                    ? (w.isOnline ? l10n.workerOnline : l10n.workerOffline)
                    : '${w.isOnline ? l10n.workerOnline : l10n.workerOffline} · ${w.hostname}',
                leading: Icon(
                  Icons.computer,
                  color: w.isOnline
                      ? null
                      : colors.textSecondary.withValues(alpha: 0.4),
                ),
                selected: w.workerId == selectedWorkerId,
                onTap: w.isOnline
                    ? () => setState(() {
                        _workerId = w.workerId;
                        final options =
                            workspaces
                                .where((ws) => ws.workerId == w.workerId)
                                .toList()
                              ..sort((a, b) {
                                if (a.isDefault != b.isDefault) {
                                  return a.isDefault ? -1 : 1;
                                }
                                return a.displayName.compareTo(b.displayName);
                              });
                        _workspaceId = options.firstOrNull?.workspaceId;
                      })
                    : null, // 离线电脑无法启动会话
                trailing: const Icon(Icons.chevron_right, size: 18),
              ),
          SectionHeader(l10n.workspacesSectionTitle),
          if (isLocked && selectedWorkspace != null)
            ListRow(
              title: selectedWorkspace.displayName,
              subtitle: selectedWorkspace.rootPath,
              leading: const Icon(Icons.folder),
            )
          else if (selectedWorkerId != null &&
              workspacesAsync.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (selectedWorkerId != null && workspacesAsync.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${workspacesAsync.error}',
                    style: TextStyle(fontSize: 14, color: colors.danger),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(workspacesProvider),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            )
          else if (selectedWorkerId != null) ...[
            for (final ws in availableWorkspaces)
              ListRow(
                title: ws.displayName,
                subtitle: ws.rootPath,
                leading: const Icon(Icons.folder),
                selected: ws.workspaceId == _workspaceId,
                onTap: () => setState(() => _workspaceId = ws.workspaceId),
                trailing: const Icon(Icons.chevron_right, size: 18),
              ),
            ListRow(
              title: l10n.workspaceCreateTitle,
              leading: const Icon(Icons.create_new_folder),
              onTap: _newWorkspace,
              trailing: const Icon(Icons.chevron_right, size: 18),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l10n.chooseComputerFirst,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          SectionHeader(l10n.sessionNameLabel),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(hintText: l10n.workspaceNameAutoHint),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                _error!,
                style: TextStyle(fontSize: 14, color: colors.danger),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: PrimaryButton(
          label: _creating ? l10n.loading : l10n.createSession,
          onPressed: selectedWorkspace == null || _creating
              ? null
              : () => _create(selectedWorkspace),
        ),
      ),
    );
  }
}
