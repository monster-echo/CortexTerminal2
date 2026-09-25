import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../core/models/workspace.dart';
import '../../../shared/widgets/corterm_ui.dart';
import '../../files/data/file_repository.dart';
import '../../sessions/data/sessions_providers.dart';
import '../data/workspace_providers.dart';

/// 远端文件夹选择页（design/02 §4）：点文件夹行进入目录，底部确认返回当前目录绝对路径。
///
/// UX 规则：
/// - 每次都从起点打开（该电脑工作区根，否则 "~"），不做记忆——记忆会让用户
///   困惑「为什么我从这个奇怪的地方开始」。
/// - 「返回上级」在任何状态下都可用（含错误/空态），不存在走不出来的目录。
/// - 顶部提供「回到起点」。
/// - 错误态提供「重试」。
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
  String _query = '';
  bool _creatingDir = false;
  int _loadSeq = 0; // 丢弃过期请求的响应（快速连续导航时）

  late final String _root =
      _startRoot(ref.read(workspacesProvider).value ?? const <Workspace>[]);
  Future<FileListing>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<FileListing> _load() {
    final seq = ++_loadSeq;
    return ref
        .read(fileRepositoryProvider)
        .listForWorker(workerId: widget.workerId, root: _root, path: _rel)
        .then((r) {
      if (seq != _loadSeq) throw _StaleLoad();
      return r;
    });
  }

  void _open(String rel) {
    setState(() {
      _rel = rel;
      _query = '';
      _future = _load();
    });
  }

  void _back() {
    if (_rel.isEmpty) return;
    _open(_rel.contains('/') ? _rel.substring(0, _rel.lastIndexOf('/')) : '');
  }

  void _toStart() => _open('');

  Future<void> _retry() async {
    setState(() => _future = _load());
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
    if (name == null || name.isEmpty) return;
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

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('选择文件夹'),
        actions: [
          IconButton(
            tooltip: '回到起点',
            icon: const Icon(Icons.home_outlined),
            onPressed: _rel.isEmpty ? null : _toStart,
          ),
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
                    worker == null
                        ? _absolute
                        : '${worker.displayName} · $_absolute',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '返回上级',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.arrow_upward,
                      size: 20,
                      color: _rel.isEmpty
                          ? colors.divider
                          : colors.textSecondary),
                  onPressed: _rel.isEmpty ? null : _back,
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
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  if (snap.error is _StaleLoad) {
                    return const SizedBox.shrink();
                  }
                  // 错误态仍保留导航出口：返回上级 / 回到起点 / 重试。
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${snap.error}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: colors.danger, fontSize: 14)),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_rel.isNotEmpty)
                              TextButton(
                                onPressed: _back,
                                child: const Text('返回上级'),
                              ),
                            TextButton(
                              onPressed: _toStart,
                              child: const Text('回到起点'),
                            ),
                            TextButton(
                              onPressed: _retry,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ],
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
                return RefreshIndicator(
                  onRefresh: () async => _open(_rel),
                  child: ListView(
                    children: [
                      if (_rel.isNotEmpty)
                        ListRow(
                          title: '..',
                          leading:
                              const Icon(Icons.arrow_upward, size: 18),
                          onTap: _back,
                        ),
                      if (dirs.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: EmptyState(
                              icon: Icons.folder_open,
                              message: q.isEmpty
                                  ? '没有子文件夹'
                                  : '无匹配「$_query」的文件夹'),
                        ),
                      for (final d in dirs)
                        ListRow(
                          title: d.name,
                          leading: const Icon(Icons.folder, size: 18),
                          onTap: () => _open(
                              _rel.isEmpty ? d.name : '$_rel/${d.name}'),
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
}

/// 过期的加载响应（用户已经导航走了）——静默丢弃。
class _StaleLoad implements Exception {}
