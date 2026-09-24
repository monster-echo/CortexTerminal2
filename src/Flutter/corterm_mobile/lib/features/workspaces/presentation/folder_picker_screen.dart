import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../core/models/workspace.dart';
import '../../../shared/widgets/corterm_ui.dart';
import '../../files/data/file_repository.dart';
import '../../sessions/data/sessions_providers.dart';
import '../data/workspace_providers.dart';

/// 远端文件夹选择页（design/02 §4）：点文件夹行进入目录，底部确认返回当前目录绝对路径。
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
  late final String _root =
      _startRoot(ref.read(workspacesProvider).value ?? const <Workspace>[]);
  late Future<FileListing> _future = _load();

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
      _future = _load();
    });
  }

  String get _absolute {
    final root = _root;
    final trimmed =
        root.endsWith('/') && root.length > 1 ? root.substring(0, root.length - 1) : root;
    return _rel.isEmpty ? trimmed : '$trimmed/$_rel';
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
        title: Text(worker?.displayName ?? '选择文件夹'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
                          child: Text('${snap.error}',
                              style: TextStyle(color: colors.danger)),
                        );
                      }
                      final dirs = snap.data!.entries
                          .where((e) => e.isDirectory)
                          .toList()
                        ..sort((a, b) => a.name.compareTo(b.name));
                      if (dirs.isEmpty) {
                        return const EmptyState(
                            icon: Icons.folder_open, message: '没有子文件夹');
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
}
