import '../../../shared/layout/adaptive_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/api/api_exception.dart';
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
  bool _duplicateName = false;
  String? _error;
  bool _queryRead = false;
  bool _returnResult = false;
  // 恢复自偏好（而非路由预选）的电脑：加载到列表后需校验在线，离线则清空。
  bool _restoredLastWorker = false;
  bool _restoreChecked = false;

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
      final prefix = ref.read(workspaceMemoryPrefixProvider);
      final prefs = ref.read(sharedPreferencesProvider);
      if (_workerId == null) {
        _workerId = prefs.getString('$prefix.last_worker');
        _restoredLastWorker = _workerId != null;
      }
      if (_workerId != null) {
        _folder = prefs.getString('$prefix.last_folder.$_workerId');
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
      _error = null;
      _duplicateName = false;
      _folder = ref
          .read(sharedPreferencesProvider)
          .getString(
            '${ref.read(workspaceMemoryPrefixProvider)}.last_folder.$_workerId',
          );
      if (_nameAutoFilled) {
        _nameController.text = _folder == '.'
            ? AppLocalizations.of(context)!.homeFolder
            : _folder?.split('/').lastOrNull ?? '';
      }
      ref
          .read(sharedPreferencesProvider)
          .setString(
            '${ref.read(workspaceMemoryPrefixProvider)}.last_worker',
            _workerId!,
          );
    });
  }

  Future<void> _pickFolder() async {
    final folder = await context.push<String>(
      '/folder-picker?workerId=$_workerId',
    );
    if (folder == null || !mounted) return;
    await ref
        .read(sharedPreferencesProvider)
        .setString(
          '${ref.read(workspaceMemoryPrefixProvider)}.last_folder.$_workerId',
          folder,
        );
    if (!mounted) return;
    setState(() {
      _folder = folder;
      _error = null;
      _duplicateName = false;
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
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final name = _nameController.text.trim();
      final existing = await ref.read(workspaceRepositoryProvider).list();
      final duplicate = existing.any(
        (workspace) =>
            workspace.workerId == _workerId &&
            workspace.name.trim().toLowerCase() == name.toLowerCase(),
      );
      if (duplicate) {
        if (!mounted) return;
        setState(() {
          _error = l10n.workspaceNameAlreadyExists;
          _duplicateName = true;
          _creating = false;
        });
        return;
      }
      await ref
          .read(sharedPreferencesProvider)
          .setString(
            '${ref.read(workspaceMemoryPrefixProvider)}.last_worker',
            _workerId!,
          );
      final ws = await ref
          .read(workspaceRepositoryProvider)
          .create(workerId: _workerId!, name: name, rootPath: _folder!);
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
        _error = e is ApiException && e.statusCode == 409
            ? l10n.workspaceNameAlreadyExists
            : '$e';
        _duplicateName = e is ApiException && e.statusCode == 409;
        _creating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    final l10n = AppLocalizations.of(context)!;
    final workersAsync = ref.watch(workersProvider);
    final workersValue = workersAsync.asData?.value;

    // 恢复自偏好的上次电脑：列表就绪后校验在线，离线则清空预选（对齐 ArkTS）。
    if (workersValue != null && _restoredLastWorker && !_restoreChecked) {
      _restoreChecked = true;
      final restored = workersValue
          .where((w) => w.workerId == _workerId)
          .firstOrNull;
      if (restored == null || !restored.isOnline) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _workerId = null;
            _folder = null;
            _nameController.clear();
            _nameAutoFilled = false;
          });
        });
      }
    }

    return AdaptivePageScaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        toolbarHeight: 52,
        title: Text(l10n.workspaceCreateTitle),
      ),
      body: SafeArea(
        top: false,
        child: workersValue != null
            ? _form(context, workersValue)
            : switch (workersAsync) {
                AsyncLoading() => const Center(
                  child: CircularProgressIndicator(),
                ),
                AsyncError(:final error) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          '$error',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.danger),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref.invalidate(workersProvider),
                        child: Text(l10n.retry),
                      ),
                    ],
                  ),
                ),
                AsyncValue(:final value) => _form(context, value ?? const []),
              },
      ),
    );
  }

  /// 文件夹行回显：主目录 / ~/相对路径 / 绝对路径（对齐 ArkTS 展示）。
  String _folderDisplay(AppLocalizations l10n) {
    final f = _folder;
    if (f == null) return l10n.selectFolderTitle;
    if (f == '.') return l10n.homeFolder;
    if (f.startsWith('./')) return '~/${f.substring(2)}';
    return f;
  }

  Future<void> _refreshWorkers() async {
    if (_creating) return;
    try {
      ref.invalidate(workersProvider);
      await ref.read(workersProvider.future);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = Localizations.localeOf(context).languageCode == 'zh'
            ? '刷新电脑失败，请下拉重试。$e'
            : 'Could not refresh computers. Pull down to retry. $e',
      );
    }
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
        !_duplicateName &&
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
          child: RefreshIndicator(
            onRefresh: _refreshWorkers,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
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
                  title: _folderDisplay(l10n),
                  icon: Icons.folder_outlined,
                  onTap: worker == null ? null : _pickFolder,
                ),
                fieldLabel(l10n.workspaceNameLabel),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _nameController,
                    onChanged: (_) => setState(() {
                      _nameAutoFilled = false;
                      _error = null;
                      _duplicateName = false;
                    }),
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
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: PrimaryButton(
            label: _creating ? l10n.loading : l10n.workspaceCreateTitle,
            onPressed: canCreate ? _create : null,
          ),
        ),
      ],
    );
  }
}
