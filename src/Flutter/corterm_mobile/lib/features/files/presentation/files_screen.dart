import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../shared/widgets/corterm_ui.dart';
import '../../../shared/widgets/states.dart' show ErrorState, showAppToast;
import '../data/file_repository.dart';

/// 远程文件（Dark Tool Context，design/05）：根目录固定 Workspace Root，
/// 面包屑导航 + 文件/文件夹列表 + 文件操作菜单 + 上传。
class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({
    super.key,
    required this.workspaceId,
    required this.workspaceName,
    required this.rootPath,
  });

  final String workspaceId;
  final String workspaceName;
  final String rootPath;

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  String _path = '';
  late Future<FileListing> _future = _load(_path);
  bool _busy = false;

  Future<FileListing> _load(String path) => ref
      .read(fileRepositoryProvider)
      .list(workspaceId: widget.workspaceId, path: path);

  void _open(String path) {
    setState(() {
      _path = path;
      _future = _load(path);
    });
  }

  String _join(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

  Future<void> _refresh() async {
    setState(() => _future = _load(_path));
    await _future;
  }

  Future<void> _upload() async {
    final result = await FilePicker.pickFiles(withData: true);
    final picked = result?.files.firstOrNull;
    if (picked == null || picked.bytes == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(fileRepositoryProvider).upload(
            workspaceId: widget.workspaceId,
            dirPath: _path,
            filename: picked.name,
            bytes: picked.bytes!,
          );
      if (!mounted) return;
      showAppToast(context, '上传完成');
      await _refresh();
    } catch (e) {
      if (mounted) showAppToast(context, '上传失败：$e', destructive: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(FileEntry entry) async {
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(fileRepositoryProvider).downloadBytes(
            workspaceId: widget.workspaceId,
            path: _join(_path, entry.name),
          );
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: entry.name)],
          text: entry.name,
        ),
      );
    } catch (e) {
      if (mounted) showAppToast(context, '下载失败：$e', destructive: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _copyPath(FileEntry entry) {
    Clipboard.setData(ClipboardData(text: _join(_path, entry.name)));
    showAppToast(context, '路径已复制');
  }

  Future<void> _rename(FileEntry entry) async {
    final newName = await _promptText(
      title: '重命名',
      label: '名称',
      initial: entry.name,
      confirmLabel: '重命名',
    );
    if (newName == null || newName.isEmpty || newName == entry.name) return;
    setState(() => _busy = true);
    try {
      await ref.read(fileRepositoryProvider).rename(
            workspaceId: widget.workspaceId,
            path: _join(_path, entry.name),
            newName: newName,
          );
      if (!mounted) return;
      showAppToast(context, '已重命名');
      await _refresh();
    } catch (e) {
      if (mounted) showAppToast(context, '重命名失败：$e', destructive: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(FileEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final c = colorsOf(dialogContext);
        return AlertDialog(
          backgroundColor: c.surfaceElevated,
          title: Text('删除${entry.isDirectory ? '文件夹' : '文件'}',
              style: TextStyle(fontSize: 18, color: c.textPrimary)),
          content: Text(
            entry.isDirectory
                ? '「${entry.name}」及其全部内容将被删除，此操作不可恢复。'
                : '「${entry.name}」将被删除，此操作不可恢复。',
            style: TextStyle(fontSize: 14, color: c.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('取消', style: TextStyle(color: c.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('删除', style: TextStyle(color: c.danger)),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(fileRepositoryProvider).delete(
            workspaceId: widget.workspaceId,
            path: _join(_path, entry.name),
          );
      if (!mounted) return;
      showAppToast(context, '已删除');
      await _refresh();
    } catch (e) {
      if (mounted) showAppToast(context, '删除失败：$e', destructive: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mkdir() async {
    final name = await _promptText(title: '新建文件夹', label: '文件夹名称', confirmLabel: '创建');
    if (name == null || name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(fileRepositoryProvider).mkdir(
            workspaceId: widget.workspaceId,
            path: _join(_path, name),
          );
      if (!mounted) return;
      showAppToast(context, '文件夹已创建');
      await _refresh();
    } catch (e) {
      if (mounted) showAppToast(context, '创建失败：$e', destructive: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createTextFile() async {
    final result = await _promptNewTextFile();
    if (result == null) return;
    final (name, content) = result;
    setState(() => _busy = true);
    try {
      await ref.read(fileRepositoryProvider).writeText(
            workspaceId: widget.workspaceId,
            path: _join(_path, name),
            content: content,
          );
      if (!mounted) return;
      showAppToast(context, '文件已创建');
      await _refresh();
    } catch (e) {
      if (mounted) showAppToast(context, '创建失败：$e', destructive: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 单行文本输入弹层（Dark Tool 风格）。返回 null 表示取消。
  Future<String?> _promptText({
    required String title,
    required String label,
    String initial = '',
    required String confirmLabel,
  }) {
    final controller = TextEditingController(text: initial);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        // Modal 路由在 Navigator 根上，需显式 Dark Theme。
        return Theme(
          data: cortermDarkToolTheme(),
          child: Builder(builder: (sheetContext) {
        final c = colorsOf(sheetContext);
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 20,
            bottom: 20 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: c.textPrimary)),
                const SizedBox(height: 16),
                Text(label,
                    style: TextStyle(fontSize: 14, color: c.textSecondary)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: TextStyle(fontSize: 16, color: c.textPrimary),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: c.surface,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: c.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: c.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: c.accent),
                    ),
                  ),
                  onSubmitted: (value) =>
                      Navigator.of(sheetContext).pop(value),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: colorsOf(context).onEmphasis,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    onPressed: () =>
                        Navigator.of(sheetContext).pop(controller.text),
                    child: Text(confirmLabel,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500)),
                  ),
                ),
              ],
            ),
          ),
        );
          }),
        );
      },
    );
  }

  /// 新建文本文件弹层：文件名 + 内容。返回 null 表示取消。
  Future<(String, String)?> _promptNewTextFile() {
    final nameController = TextEditingController();
    final contentController = TextEditingController();
    return showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        // Modal 路由在 Navigator 根上，需显式 Dark Theme。
        return Theme(
          data: cortermDarkToolTheme(),
          child: Builder(builder: (sheetContext) {
        final c = colorsOf(sheetContext);
        InputDecoration inputDecoration(String hint) => InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(fontSize: 14, color: c.textSecondary),
              filled: true,
              fillColor: c.surface,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: c.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: c.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: c.accent),
              ),
            );
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 20,
            bottom: 20 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('新建文本文件',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: c.textPrimary)),
                const SizedBox(height: 16),
                Text('文件名',
                    style: TextStyle(fontSize: 14, color: c.textSecondary)),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style: TextStyle(fontSize: 16, color: c.textPrimary),
                  decoration: inputDecoration('例如 notes.txt'),
                ),
                const SizedBox(height: 16),
                Text('内容',
                    style: TextStyle(fontSize: 14, color: c.textSecondary)),
                const SizedBox(height: 8),
                TextField(
                  controller: contentController,
                  style: TextStyle(fontSize: 16, color: c.textPrimary),
                  maxLines: 5,
                  minLines: 3,
                  decoration: inputDecoration('文件内容（可为空）'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: colorsOf(context).onEmphasis,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    onPressed: () {
                      final name = nameController.text;
                      if (name.isEmpty) return;
                      Navigator.of(sheetContext)
                          .pop((name, contentController.text));
                    },
                    child: const Text('创建',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500)),
                  ),
                ),
              ],
            ),
          ),
        );
          }),
        );
      },
    );
  }

  void _preview(FileEntry entry) {
    context.push(
      '/workspaces/${widget.workspaceId}/files/preview'
      '?path=${Uri.encodeComponent(_join(_path, entry.name))}'
      '&name=${Uri.encodeComponent(entry.name)}'
      '&size=${entry.sizeBytes}',
    );
  }

  bool _isTextFile(String name) {
    const exts = [
      '.txt', '.log', '.json', '.js', '.ts', '.jsx', '.tsx', '.py', '.sh',
      '.md', '.conf', '.yaml', '.yml', '.toml', '.xml', '.html', '.css',
      '.ini', '.env', '.sql', '.c', '.h', '.cpp', '.hpp', '.java', '.go',
      '.rs', '.rb', '.php', '.dart',
    ];
    final lower = name.toLowerCase();
    return exts.any(lower.endsWith);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: cortermDarkToolTheme(),
      child: Builder(
        builder: (context) {
          final c = colorsOf(context);
          return Scaffold(
            backgroundColor: c.background,
            appBar: AppBar(
              title: Text(widget.workspaceName.isEmpty ? '电脑' : widget.workspaceName),
              actions: [
                PopupMenuButton<String>(
                  icon: _busy
                      ? Icon(Icons.add, color: c.textSecondary)
                      : const Icon(Icons.add),
                  tooltip: '新建',
                  color: c.surfaceElevated,
                  onSelected: (action) {
                    switch (action) {
                      case 'upload':
                        _upload();
                      case 'mkdir':
                        _mkdir();
                      case 'newText':
                        _createTextFile();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'upload', child: Text('上传文件')),
                    PopupMenuItem(value: 'mkdir', child: Text('新建文件夹')),
                    PopupMenuItem(value: 'newText', child: Text('新建文本文件')),
                  ],
                ),
              ],
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Breadcrumb(path: _path, rootLabel: widget.rootPath, onNavigate: _open),
                Divider(color: c.divider, height: 1),
                Expanded(
                  child: FutureBuilder<FileListing>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return ErrorState(
                          message: '${snap.error}',
                          onRetry: () => _open(_path),
                        );
                      }
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final entries = snap.data!.entries.toList()
                        ..sort((a, b) {
                          if (a.isDirectory != b.isDirectory) {
                            return a.isDirectory ? -1 : 1;
                          }
                          return a.name.compareTo(b.name);
                        });
                      if (entries.isEmpty) {
                        return const EmptyState(
                          icon: Icons.folder_open,
                          message: '此文件夹为空',
                        );
                      }
                      return ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, i) =>
                            _EntryTile(entry: entries[i], screen: this),
                      );
                    },
                  ),
                ),
                if (_busy) const LinearProgressIndicator(minHeight: 2),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.screen});

  final FileEntry entry;
  final _FilesScreenState screen;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final subtitle = entry.isDirectory
        ? null
        : '${_fmtSize(entry.sizeBytes)} · ${_fmtTime(entry.modifiedUtc)}';
    return ListTile(
      leading: Icon(
        entry.isDirectory ? Icons.folder : Icons.insert_drive_file_outlined,
        color: entry.isDirectory ? c.accent : c.textSecondary,
      ),
      title: Text(entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 16, color: c.textPrimary)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: TextStyle(fontSize: 13, color: c.textSecondary)),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_horiz, color: c.textSecondary),
        color: c.surfaceElevated,
        onSelected: (action) {
          switch (action) {
            case 'download':
              screen._download(entry);
            case 'copy':
              screen._copyPath(entry);
            case 'rename':
              screen._rename(entry);
            case 'delete':
              screen._delete(entry);
          }
        },
        itemBuilder: (_) => [
          if (!entry.isDirectory)
            const PopupMenuItem(value: 'download', child: Text('下载')),
          const PopupMenuItem(value: 'copy', child: Text('复制路径')),
          const PopupMenuItem(value: 'rename', child: Text('重命名')),
          const PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
      onTap: entry.isDirectory
          ? () => screen._open(screen._join(screen._path, entry.name))
          : (screen._isTextFile(entry.name)
              ? () => screen._preview(entry)
              : null),
    );
  }
}

/// 面包屑：`电脑 > 当前路径`，各级可点回跳。
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({
    required this.path,
    required this.rootLabel,
    required this.onNavigate,
  });

  final String path;
  final String rootLabel;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          for (final (i, segment) in ['电脑', ...segments].indexed) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.chevron_right,
                    size: 16, color: c.textSecondary),
              ),
            InkWell(
              onTap: i == 0 ? () => onNavigate('') : () {
                final target = segments.take(i - 1).join('/');
                onNavigate(target);
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Text(
                  segment,
                  style: TextStyle(
                    fontSize: 14,
                    color: i == ['电脑', ...segments].length - 1
                        ? c.textPrimary
                        : c.accent,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

String _fmtTime(DateTime? utc) {
  if (utc == null) return '';
  final local = utc.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
