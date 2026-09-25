import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/corterm_theme.dart';
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
      );
      // 名称可选：非空时创建后重命名（Session 无类型，仅 shell）。
      final name = _nameController.text.trim();
      if (name.isNotEmpty) {
        await repo.rename(sessionId: s.sessionId, name: name);
      }
      if (mounted) context.pushReplacement('/sessions/${s.sessionId}');
    } catch (e) {
      setState(() {
        _error = '$e';
        _creating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    final workspaces = ref.watch(workspacesProvider).value ?? const <Workspace>[];
    final lockedWorkspace =
        workspaces.where((w) => w.workspaceId == _workspaceId).firstOrNull;
    final workers = ref.watch(workersProvider).value ?? const [];

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('新建会话'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionHeader('电脑'),
          if (lockedWorkspace != null)
            ListRow(
              title: workers
                      .where((w) => w.workerId == lockedWorkspace.workerId)
                      .map((w) => w.displayName)
                      .firstOrNull ??
                  lockedWorkspace.workerId,
              leading: const Icon(Icons.computer),
            )
          else
            for (final w in workers.toList()
              ..sort((a, b) {
                if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
                return a.displayName.compareTo(b.displayName);
              }))
              ListRow(
                title: w.displayName,
                subtitle: '${w.isOnline ? w.hostname : '离线（不可选） · ${w.hostname}'}',
                leading: Icon(Icons.computer,
                    color: w.isOnline ? null : colors.textSecondary.withValues(alpha: 0.4)),
                selected: w.workerId == _workerId,
                onTap: w.isOnline
                    ? () => setState(() {
                          _workerId = w.workerId;
                          _workspaceId = null; // 换电脑后清空已选工作区
                        })
                    : null, // 离线电脑无法启动会话
                trailing: const Icon(Icons.chevron_right, size: 18),
              ),
          SectionHeader('工作区'),
          if (lockedWorkspace != null)
            ListRow(
              title: lockedWorkspace.displayName,
              subtitle: lockedWorkspace.rootPath,
              leading: const Icon(Icons.folder),
            )
          else if (_workerId != null)
            for (final ws in workspaces.where((w) => w.workerId == _workerId))
              ListRow(
                title: ws.displayName,
                subtitle: ws.rootPath,
                leading: const Icon(Icons.folder),
                selected: ws.workspaceId == _workspaceId,
                onTap: () => setState(() => _workspaceId = ws.workspaceId),
                trailing: const Icon(Icons.chevron_right, size: 18),
              )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('先选择电脑',
                  style: TextStyle(fontSize: 13)),
            ),
          SectionHeader('名称（可选）'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(hintText: '留空则自动命名'),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(_error!,
                  style: TextStyle(fontSize: 14, color: colors.danger)),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: PrimaryButton(
              label: '创建会话',
              onPressed: (lockedWorkspace == null && _workspaceId == null) ||
                      _creating
                  ? null
                  : () => _create(lockedWorkspace ??
                          workspaces
                              .where((w) => w.workspaceId == _workspaceId)
                              .first),
            ),
          ),
        ],
      ),
    );
  }
}
