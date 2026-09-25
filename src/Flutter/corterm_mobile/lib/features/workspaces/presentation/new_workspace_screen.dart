import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../core/models/worker.dart';
import '../../../shared/widgets/corterm_ui.dart';
import '../../sessions/data/sessions_providers.dart';
import '../../workers/data/workspace_repository.dart';
import '../data/workspace_providers.dart';

/// 新建工作区（design/02 §3）：电脑（必填）→ 文件夹（必填）→ 名称 → 创建。
class NewWorkspaceScreen extends ConsumerStatefulWidget {
  const NewWorkspaceScreen({super.key});

  @override
  ConsumerState<NewWorkspaceScreen> createState() => _NewWorkspaceScreenState();
}

class _NewWorkspaceScreenState extends ConsumerState<NewWorkspaceScreen> {
  String? _workerId;
  String? _folder;
  bool _nameAutoFilled = false;
  bool _creating = false;
  String? _error;
  bool _queryRead = false;

  final _nameController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 路由 query 预选电脑（/workspaces/new?workerId=…），可缺省。
    // GoRouterState 是继承组件：只能在 didChangeDependencies/build 里读。
    if (_workerId == null && !_queryRead) {
      _queryRead = true;
      final preselect =
          GoRouterState.of(context).uri.queryParameters['workerId'];
      if (preselect != null && preselect.isNotEmpty) _workerId = preselect;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickWorker() async {
    final selected = await context.push<WorkerSummary>('/workers/select');
    if (selected == null) return;
    setState(() {
      _workerId = selected.workerId;
      _folder = null; // 换电脑后原文件夹无效
    });
  }

  Future<void> _pickFolder() async {
    final folder =
        await context.push<String>('/folder-picker?workerId=$_workerId');
    if (folder == null) return;
    setState(() {
      _folder = folder;
      // 名称默认取文件夹 basename，用户可改（只在第一次带入时自动填）。
      if (_nameController.text.isEmpty || _nameAutoFilled) {
        _nameController.text =
            folder.split('/').where((s) => s.isNotEmpty).last;
        _nameAutoFilled = true;
      }
    });
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final ws = await ref.read(workspaceRepositoryProvider).create(
            workerId: _workerId!,
            name: _nameController.text,
            rootPath: _folder!,
          );
      // 新工作区不在缓存列表里，先失效再进详情，否则详情页判为不存在。
      if (mounted) {
        ref.invalidate(workspacesProvider);
        context.pushReplacement('/workspaces/${ws.workspaceId}');
      }
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
    final workersAsync = ref.watch(workersProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('新建工作区'),
      ),
      body: switch (workersAsync) {
        AsyncLoading() => const Center(child: CircularProgressIndicator()),
        AsyncError(:final error) => Center(
            child: Text('$error', style: TextStyle(color: colors.danger))),
        AsyncValue(:final value) => _form(context, value ?? const []),
      },
    );
  }

  Widget _form(BuildContext context, List<WorkerSummary> workers) {
    final colors = colorsOf(context);
    final worker =
        workers.where((w) => w.workerId == _workerId).firstOrNull;
    final canCreate = worker != null && _folder != null && !_creating;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        SectionHeader('电脑'),
        ListRow(
          title: worker?.displayName ?? '请选择电脑',
          subtitle: worker?.hostname,
          leading: const Icon(Icons.computer),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickWorker,
        ),
        SectionHeader('文件夹'),
        ListRow(
          title: _folder ?? '请选择文件夹',
          leading: const Icon(Icons.folder),
          onTap: worker == null ? null : _pickFolder,
          trailing: worker == null
              ? null
              : const Icon(Icons.chevron_right),
        ),
        SectionHeader('名称'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _nameController,
            decoration: const InputDecoration(hintText: '工作区名称'),
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
            label: '创建工作区',
            onPressed: canCreate ? _create : null,
          ),
        ),
      ],
    );
  }
}
