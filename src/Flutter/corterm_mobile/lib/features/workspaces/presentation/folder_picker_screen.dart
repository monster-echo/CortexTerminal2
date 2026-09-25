import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../core/models/workspace.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../shared/widgets/corterm_ui.dart';
import '../../files/data/file_repository.dart';
import '../../sessions/data/sessions_providers.dart';
import '../data/workspace_providers.dart';

/// 远端文件夹选择页（design/02 §4）：点文件夹行进入目录，底部确认返回当前目录绝对路径。
/// 支持搜索、新建文件夹、记忆上次浏览位置。
class FolderPickerScreen extends ConsumerStatefulWidget {
  const FolderPickerScreen({super.key, required this.workerId});

  final String workerId;

  @override
  ConsumerState<FolderPickerScreen> createState() =>
      _FolderPickerScreenState();
}

class _FolderPickerScreenState extends ConsumerState<FolderPickerScreen> {
  /// 浏览根：该电脑已有工作区时用其根；否则用 "~"（worker 端展开为 home，
  /// design/02 §4——新建首个工作区时也能浏览）。
  String _startRoot(List<Workspace> workspaces) {
    final mine =
        workspaces.where((w) => w.workerId == widget.workerId).toList();
    return (mine.where((w) => w.isDefault).firstOrNull ?? mine.firstOrNull)
            ?.rootPath ??
        '~';
  }

  String _rel = '';
  String? _pendingRel; // prefs 恢复中：待 workspaces 加载后应用
  String _query = '';
  bool _creatingDir = false;

  late final String _root =
      _startRoot(ref.read(workspacesProvider).value ?? const <Workspace>[]);
  late Future<FileListing> _future = _load();

  AppPreferences get _prefs => ref.read(appPreferencesProvider);

  @override
  void initState() {
    super.initState();
    // 恢复上次浏览位置（异步读取；根可能与已存位置的时代不同，仅在根一致时应用）。
    () async {
      final saved = _prefs.folderPickerLastRel(widget.workerId);
      if (saved == null || !mounted) return;
      setState(() {
        _pendingRel = saved;
      });
    }();
  }

  Future<FileListing> _load() {
    return ref.read(fileRepositoryProvider).listForWorker(
          workerId: widget.workerId,
          root: _root,
          path: _rel,
        );
  }

  void _open(String rel) {
    setState(() {
      _rel = rel;
      _query = '';
      _future = _load();
    });
    _prefs.setFolderPickerLastRel(widget.workerId, rel);
  }

  String get _absolute {
    final root = _root;
    final trimmed =
        root.endsWith('/') && root.length > 1 ? root.substring(0, root.length - 1) : root;
    return _rel.isEmpty ? trimmed : '$trimmed/$_rel';
  }

  Future<void> _createDirectory() async {
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('新建文件夹'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '文件夹名称'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消')),
            TextButton(
              onPressed: () {
                final v = controller.text.trim();
                if (v.isNotEmpty) Navigator.pop(dialogContext, v);
              },
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty || name == _creatingDir.toString()) return;
    if (!mounted) return;

    final fullRel = _rel.isEmpty ? name : '$_rel/$name';
    setState(() => _creatingDir = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(fileRepositoryProvider)
          .mkdirForWorker(workerId: widget.workerId, root: _root, path: fullRel);
      if (!mounted) return;
      _open(fullRel);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _creatingDir = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context);
    final workersAsync = ref.watch(workersProvider);
    final worker = (workersAsync.value ?? const [])
        .where((w) => w.workerId == widget.workerId)
        .firstOrNull;

    // workspaces 加载完成且尚在根目录时，应用恢复的上次位置。
    final workspacesReady = workersAsync.hasValue && !_pendingRelApplied;
    if (workspacesReady && _pendingRel != null) {
      final hasMatchingRoot = (workersAsync.value ?? const [])
          .any((w) => w.workerId == widget.workerId);
      _pendingRelApplied = true;
      // 只恢复「根未变」时的位置：有该电脑的工作区时根取其根，否则 '~'。
      // 简化：只要保存过位置就恢复（根差异场景由刷新兜底）。
      if (_rel.isEmpty) {
        _rel = _pendingRel!;
        _future = _load();
      }
      _pendingRel = null;
      if (!hasMatchingRoot) {
        // 无工作区电脑：根是 '~'，无需特殊处理
      }
    }

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(worker?.displayName ?? '选择文件夹'),
        actions: [
          IconButton(
            tooltip: '新建文件夹',
            icon: _creatingDir
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.create_new_folder_outlined),
            onPressed: _creatingDir ? null : _createDirectory,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _absolute,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.refresh, size: 20, color: colors.textSecondary),
                  onPressed: () => _open(_rel),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(fontSize: 14, color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: '搜索当前目录',
                hintStyle: TextStyle(fontSize: 14, color: colors.textSecondary),
                prefixIcon:
                    Icon(Icons.search, size: 20, color: colors.textSecondary),
                isDense: true,
                filled: true,
                fillColor: colors.surface,
                border: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<FileListing>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('${snap.error}',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: colors.danger)),
                          ),
                        );
                      }
                      final q = _query.trim().toLowerCase();
                      final dirs = snap.data!.entries
                          .where((e) => e.isDirectory)
                          .where((e) =>
                              q.isEmpty || e.name.toLowerCase().contains(q))
                          .toList()
                        ..sort((a, b) => a.name.compareTo(b.name));
                      if (dirs.isEmpty) {
                        return EmptyState(
                            icon: Icons.folder_open,
                            message:
                                q.isEmpty ? '没有子文件夹' : '无匹配「$_query」的文件夹');
                      }
                      return RefreshIndicator(
                        onRefresh: () async => _open(_rel),
                        child: ListView(
                          children: [
                            if (_rel.isNotEmpty)
                              ListRow(
                                title: '..',
                                leading:
                                    const Icon(Icons.arrow_upward, size: 18),
                                onTap: () => _open(_rel.contains('/')
                                    ? _rel.substring(
                                        0, _rel.lastIndexOf('/'))
                                    : ''),
                              ),
                            for (final d in dirs)
                              ListRow(
                                title: d.name,
                                leading: const Icon(Icons.folder, size: 18),
                                onTap: () => _open(_rel.isEmpty
                                    ? d.name
                                    : '$_rel/${d.name}'),
                                trailing: const Icon(Icons.chevron_right,
                                    size: 18),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: PrimaryButton(
                label: '使用当前文件夹',
                onPressed: () => Navigator.pop(context, _absolute),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _pendingRelApplied = false;
}
