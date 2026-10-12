import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/storage/app_preferences.dart';
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
  bool _returnResult = false;

  final _nameController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 路由 query 预选电脑（/workspaces/new?workerId=…），可缺省。
    // GoRouterState 是继承组件：只能在 didChangeDependencies/build 里读。
    if (_workerId == null && !_queryRead) {
      _queryRead = true;
      final params = GoRouterState.of(context).uri.queryParameters;
      final preselect = params['workerId'];
      if (preselect != null && preselect.isNotEmpty) _workerId = preselect;
      final prefs = ref.read(sharedPreferencesProvider);
      _workerId ??= prefs.getString('workspace.last_worker');
      if (_workerId != null) {
        _folder = prefs.getString('workspace.last_folder.$_workerId');
      }
      if (_folder != null) {
        _nameController.text = _folder == '.'
            ? AppLocalizations.of(context)!.homeFolder
            : _folder!.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '';
        _nameAutoFilled = true;
      }
      // returnResult=1：由调用方（新建会话流程）push 进入，创建成功后带回结果。
      _returnResult = params['returnResult'] == '1';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickWorker() async {
    final selected = await context.push<WorkerSummary>('/workers/select');
    if (selected == null || !mounted) return;
    setState(() {
      _workerId = selected.workerId;
      _folder = ref
          .read(sharedPreferencesProvider)
          .getString('workspace.last_folder.$_workerId');
      if (_nameAutoFilled) {
        _nameController.text = _folder == '.'
            ? AppLocalizations.of(context)!.homeFolder
            : _folder?.split('/').lastOrNull ?? '';
      }
      ref
          .read(sharedPreferencesProvider)
          .setString('workspace.last_worker', _workerId!);
    });
  }

  Future<void> _pickFolder() async {
    final folder = await context.push<String>(
      '/folder-picker?workerId=$_workerId',
    );
    if (folder == null || !mounted) return;
    await ref
        .read(sharedPreferencesProvider)
        .setString('workspace.last_folder.$_workerId', folder);
    if (!mounted) return;
    setState(() {
      _folder = folder;
      // 名称默认取文件夹 basename，用户可改（只在第一次带入时自动填）。
      if (_nameController.text.isEmpty || _nameAutoFilled) {
        _nameController.text = folder == '.'
            ? AppLocalizations.of(context)!.homeFolder
            : folder.split('/').where((s) => s.isNotEmpty).lastOrNull ??
                  AppLocalizations.of(context)!.homeFolder;
        _nameAutoFilled = true;
      }
    });
  }

  Future<void> _create() async {
    if (_creating ||
        _workerId == null ||
        _folder == null ||
        _nameController.text.trim().isEmpty) {
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await ref
          .read(sharedPreferencesProvider)
          .setString('workspace.last_worker', _workerId!);
      final ws = await ref
          .read(workspaceRepositoryProvider)
          .create(
            workerId: _workerId!,
            name: _nameController.text,
            rootPath: _folder!,
          );
      // 新工作区不在缓存列表里，先失效；流程内调用时把结果带回调用方。
      if (mounted) {
        ref.invalidate(workspacesProvider);
        if (_returnResult) {
          context.pop(ws);
        } else {
          context.pushReplacement('/workspaces/${ws.workspaceId}');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _creating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    final l10n = AppLocalizations.of(context)!;
    final workersAsync = ref.watch(workersProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        toolbarHeight: 52,
        title: Text(l10n.workspaceCreateTitle),
        actions: [
          IconButton(
            tooltip: Localizations.localeOf(context).languageCode == 'zh'
                ? '刷新电脑'
                : 'Refresh computers',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(workersProvider),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: switch (workersAsync) {
          AsyncLoading() => const Center(child: CircularProgressIndicator()),
          AsyncError(:final error) => Center(
            child: Text('$error', style: TextStyle(color: colors.danger)),
          ),
          AsyncValue(:final value) => _form(context, value ?? const []),
        },
      ),
    );
  }

  Widget _form(BuildContext context, List<WorkerSummary> workers) {
    final colors = colorsOf(context);
    final l10n = AppLocalizations.of(context)!;
    final worker = workers.where((w) => w.workerId == _workerId).firstOrNull;
    final canCreate =
        worker != null &&
        worker.isOnline &&
        _folder != null &&
        _nameController.text.trim().isNotEmpty &&
        !_creating;

    Widget fieldLabel(String text, {bool first = false}) => Padding(
      padding: EdgeInsets.fromLTRB(16, first ? 16 : 20, 16, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: colors.textSecondary,
        ),
      ),
    );

    Widget selectionRow({
      required String title,
      String? subtitle,
      required IconData icon,
      required VoidCallback? onTap,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.divider),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: colors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              fieldLabel(l10n.computersTitle, first: true),
              selectionRow(
                title: worker?.displayName ?? l10n.selectComputerTitle,
                subtitle: worker?.hostname,
                icon: Icons.computer_outlined,
                onTap: _pickWorker,
              ),
              fieldLabel(l10n.selectFolderTitle),
              selectionRow(
                title: _folder == '.'
                    ? l10n.homeFolder
                    : _folder ?? l10n.selectFolderTitle,
                icon: Icons.folder_outlined,
                onTap: worker == null ? null : _pickFolder,
              ),
              fieldLabel(l10n.workspaceNameLabel),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _nameController,
                  onChanged: (_) => setState(() => _nameAutoFilled = false),
                  decoration: InputDecoration(
                    hintText: l10n.workspaceNameLabel,
                    filled: true,
                    fillColor: colors.surfaceElevated,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.accent),
                    ),
                  ),
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
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: PrimaryButton(
            label: l10n.workspaceCreateTitle,
            onPressed: canCreate ? _create : null,
          ),
        ),
      ],
    );
  }
}
