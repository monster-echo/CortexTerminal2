import 'dart:convert';
import 'dart:math';

import '../../../shared/layout/adaptive_sheet.dart';
import '../../../shared/layout/adaptive_page_scaffold.dart';
import 'file_error_message.dart';

import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/corterm_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../shared/widgets/corterm_ui.dart';
import '../../../shared/widgets/states.dart' show ErrorState, showAppToast;
import '../data/file_repository.dart';
import '../data/file_transfer_control.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../workspaces/data/workspace_providers.dart';
import '../../sessions/data/sessions_providers.dart';

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
  // workspace 模式：按 workspaceId 恢复上次浏览路径（任务 A）。
  late String _path;
  late Future<FileListing> _future = _load(_path);
  bool _busy = false;
  bool _picking = false;
  bool _editing = false;
  String _query = '';
  FileTransferControl? _transfer;
  String? _transferName;
  String? _transferError;
  @override
  void dispose() {
    _transfer?.cancel();
    super.dispose();
  }

  String _routeLabel(String route) => switch (route) {
    'negotiating' => _tr('准备传输', 'Preparing transfer'),
    'lan' => _tr('局域网直连', 'Local network'),
    'p2p' => _tr('设备直连', 'Device connection'),
    'public' => _tr('公网直连', 'Direct connection'),
    'relay' => _tr('安全中转', 'Secure relay'),
    _ => route,
  };
  String _tr(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  void initState() {
    super.initState();
    _path =
        ref.read(appPreferencesProvider).filesLastPath(widget.workspaceId) ??
        '';
  }

  Future<FileListing> _load(String path) async {
    final repository = ref.read(fileRepositoryProvider);
    try {
      return await repository.list(workspaceId: widget.workspaceId, path: path);
    } on ApiException catch (e) {
      // 恢复的记忆路径已失效（产品行为）：清记忆、回根加载，并明确告知用户。
      // 其余错误照常上抛（CLAUDE.md：禁止 fallback 吞错）。
      if (path.isEmpty || !isStalePathError(e)) rethrow;
      await ref
          .read(appPreferencesProvider)
          .setFilesLastPath(widget.workspaceId, '');
      if (!mounted) rethrow;
      showAppToast(context, '原目录已不存在，已返回根目录');
      setState(() => _path = '');
      return repository.list(workspaceId: widget.workspaceId, path: '');
    }
  }

  void _open(String path) {
    if (_busy) return;
    setState(() {
      _path = path;
      _future = _load(path);
    });
    ref.read(appPreferencesProvider).setFilesLastPath(widget.workspaceId, path);
  }

  String _join(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

  Future<void> _refresh() async {
    setState(() {
      _future = _load(_path);
    });
    await _future;
  }

  Future<void> _runTransfer(
    String name,
    Future<void> Function(FileTransferControl) run,
  ) async {
    if (_busy || !mounted) return;
    final control = FileTransferControl();
    setState(() {
      _busy = true;
      _transfer = control;
      _transferName = name;
      _transferError = null;
    });
    try {
      await run(control);
      if (mounted) showAppToast(context, _tr('传输完成', 'Transfer complete'));
    } catch (error) {
      if (mounted) {
        setState(
          () => _transferError =
              error is DioException && CancelToken.isCancel(error)
              ? _tr(
                  '传输已取消。上传若已在远端完成，请刷新核对结果。',
                  'Transfer cancelled. Refresh to check whether an upload already completed remotely.',
                )
              : fileErrorMessage(context, error),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _transfer = null;
        });
        try {
          await _refresh();
        } catch (error) {
          if (mounted) {
            setState(() => _transferError = fileErrorMessage(context, error));
          }
        }
      }
      control.dispose();
    }
  }

  Future<void> _upload() async {
    if (_busy || _picking) return;
    FilePickerResult? result;
    setState(() => _picking = true);
    try {
      result = await FilePicker.pickFiles(withData: true);
    } catch (error) {
      if (mounted) showAppToast(context, '$error', destructive: true);
      return;
    } finally {
      if (mounted) setState(() => _picking = false);
    }
    final picked = result?.files.firstOrNull;
    if (picked == null || !mounted) return;
    if (picked.bytes == null) {
      showAppToast(
        context,
        _tr('无法读取选择的文件。', 'Cannot read the selected file.'),
        destructive: true,
      );
      return;
    }
    try {
      final listing = await _future;
      if (!mounted) return;
      if (listing.entries.any((entry) => entry.name == picked.name)) {
        final confirmed = await showConfirmDialog(
          context: context,
          title: _tr('覆盖同名文件？', 'Replace existing file?'),
          body: _tr(
            '上传将覆盖「${picked.name}」，原内容无法恢复。',
            'Uploading replaces "${picked.name}". The original contents cannot be recovered.',
          ),
          confirmLabel: _tr('覆盖并上传', 'Replace and upload'),
          destructive: true,
        );
        if (!confirmed || !mounted) return;
      }
      final path = _path;
      await _runTransfer(
        picked.name,
        (control) => ref
            .read(fileRepositoryProvider)
            .upload(
              workspaceId: widget.workspaceId,
              dirPath: path,
              filename: picked.name,
              bytes: picked.bytes!,
              control: control,
            ),
      );
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          fileErrorMessage(context, error),
          destructive: true,
        );
      }
    }
  }

  Future<void> _download(FileEntry entry) async {
    final path = _join(_path, entry.name);
    await _runTransfer(entry.name, (control) async {
      final bytes = await ref
          .read(fileRepositoryProvider)
          .downloadBytes(
            workspaceId: widget.workspaceId,
            path: path,
            control: control,
          );
      control.checkCancelled();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: entry.name)],
          text: entry.name,
        ),
      );
    });
  }

  void _copyPath(FileEntry entry) {
    Clipboard.setData(ClipboardData(text: _join(_path, entry.name)));
    showAppToast(context, '路径已复制');
  }

  Future<void> _rename(FileEntry entry) async {
    final path = _join(_path, entry.name);
    await _mutate(
      title: _tr('重命名', 'Rename'),
      initialName: entry.name,
      submit: (name, _) => ref
          .read(fileRepositoryProvider)
          .rename(workspaceId: widget.workspaceId, path: path, newName: name),
    );
  }

  String get _trashKey =>
      '${ref.read(workspaceMemoryPrefixProvider)}.trash.${widget.workspaceId}';

  List<Map<String, dynamic>> _trashRecords() {
    final raw = ref.read(sharedPreferencesProvider).getString(_trashKey);
    return raw == null
        ? []
        : (jsonDecode(raw) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
  }

  Future<void> _saveTrash(List<Map<String, dynamic>> records) async {
    if (!await ref
        .read(sharedPreferencesProvider)
        .setString(_trashKey, jsonEncode(records))) {
      throw StateError('Unable to save recovery record');
    }
  }

  Future<void> _delete(FileEntry entry) async {
    if (_busy) return;
    final confirmed = await showConfirmDialog(
      context: context,
      title: _tr('移到回收站', 'Move to trash'),
      body: _tr(
        '「${entry.name}」将保存在电脑工作区的回收目录中，不会自动清理。可从本机的“最近删除”恢复。',
        '“${entry.name}” will be kept in the computer’s workspace recovery folder without automatic cleanup. Restore it from Recently deleted on this device.',
      ),
      confirmLabel: _tr('移到回收站', 'Move to trash'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      final random = Random.secure();
      final id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final records = _trashRecords();
      final record = <String, dynamic>{
        'id': id,
        'path': _join(_path, entry.name),
        'pending': true,
      };
      records.add(record);
      // Save the receipt before sending: a lost acknowledgement must remain recoverable.
      await _saveTrash(records);
      await ref
          .read(fileRepositoryProvider)
          .trash(
            workspaceId: widget.workspaceId,
            path: record['path'] as String,
            trashId: id,
          );
      record['pending'] = false;
      await _saveTrash(records);
      if (!mounted) return;
      showAppToast(
        context,
        _tr(
          '已移到回收站，可在最近删除中恢复',
          'Moved to trash. Restore from Recently deleted.',
        ),
      );
      setState(() {
        _future = _load(_path);
      });
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          _tr(
            '移入回收站未确认；请检查最近删除。需要电脑和服务端均支持恢复功能。',
            'Move not confirmed. Check Recently deleted. Both the computer and server must support recovery.',
          ),
          destructive: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showTrash() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _editing = true;
    });
    try {
      final records = _trashRecords();
      if (!mounted) return;
      await showCortermSheet<void>(
        context: context,
        builder: (_) => _TrashRecoverySheet(
          records: records,
          restore: (record) async {
            await ref
                .read(fileRepositoryProvider)
                .restoreTrash(
                  workspaceId: widget.workspaceId,
                  trashId: record['id'] as String,
                );
            final updated = _trashRecords()
              ..removeWhere((e) => e['id'] == record['id']);
            await _saveTrash(updated);
            if (mounted) {
              setState(() {
                _future = _load(_path);
              });
            }
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        showAppToast(context, fileErrorMessage(context, e), destructive: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _editing = false;
        });
      }
    }
  }

  Future<void> _mkdir() async {
    final path = _path;
    await _mutate(
      title: _tr('新建文件夹', 'New folder'),
      submit: (name, _) => ref
          .read(fileRepositoryProvider)
          .mkdir(workspaceId: widget.workspaceId, path: _join(path, name)),
    );
  }

  Future<void> _createTextFile() async {
    final path = _path;
    await _mutate(
      title: _tr('新建文本文件', 'New text file'),
      withContent: true,
      submit: (name, content) => ref
          .read(fileRepositoryProvider)
          .writeText(
            workspaceId: widget.workspaceId,
            path: _join(path, name),
            content: content,
          ),
    );
  }

  Future<void> _mutate({
    required String title,
    String initialName = '',
    bool withContent = false,
    required Future<void> Function(String, String) submit,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _editing = true;
    });
    try {
      final listing = await _future;
      if (!mounted) return;
      final changed = await showAdaptiveModalBottomSheet<bool>(
        context: context,
        builder: (_) => _FileMutationSheet(
          title: title,
          initialName: initialName,
          withContent: withContent,
          existingNames: listing.entries.map((entry) => entry.name).toSet(),
          submit: submit,
        ),
      );
      if (!mounted || changed != true) return;
      setState(() {
        _future = _load(_path);
      });
      showAppToast(context, _tr('操作完成', 'Done'));
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          fileErrorMessage(context, error),
          destructive: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _editing = false;
        });
      }
    }
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
      '.txt',
      '.log',
      '.json',
      '.js',
      '.ts',
      '.jsx',
      '.tsx',
      '.py',
      '.sh',
      '.md',
      '.conf',
      '.yaml',
      '.yml',
      '.toml',
      '.xml',
      '.html',
      '.css',
      '.ini',
      '.env',
      '.sql',
      '.c',
      '.h',
      '.cpp',
      '.hpp',
      '.java',
      '.go',
      '.rs',
      '.rb',
      '.php',
      '.dart',
    ];
    final lower = name.toLowerCase();
    return exts.any(lower.endsWith);
  }

  void _showTransferConnection(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String tr(String cn, String en) => zh ? cn : en;
    String label(String route) => switch (route) {
      'lan' => tr('局域网直连', 'LAN direct'),
      'p2p' => tr('P2P 打洞直连', 'P2P hole-punched connection'),
      'public' => tr('公网直连', 'Public direct'),
      _ => tr('安全中继', 'Secure relay'),
    };
    final workspace = ref
        .read(workspacesProvider)
        .asData
        ?.value
        .where((w) => w.workspaceId == widget.workspaceId)
        .firstOrNull;
    final worker = ref
        .read(workersProvider)
        .asData
        ?.value
        .where((w) => w.workerId == workspace?.workerId)
        .firstOrNull;
    final root = workspace?.rootPath ?? widget.rootPath;
    final workspaceName = workspace?.displayName ?? widget.workspaceName;
    showAdaptiveModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 280),
        reverseDuration: Duration(milliseconds: 220),
      ),
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .55,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ValueListenableBuilder<List<TransferRecord>>(
              valueListenable: ref.read(transferRoutesProvider),
              builder: (context, allHistory, _) {
                final history = allHistory
                    .where(
                      (event) => event.scope.workspaceId == widget.workspaceId,
                    )
                    .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('文件传输连接', 'File transfer connection'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        '${worker?.displayName ?? workspace?.workerId ?? '电脑'} · $workspaceName',
                        '${worker?.displayName ?? workspace?.workerId ?? 'Computer'} · $workspaceName',
                      ),
                    ),
                    if (root.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: SelectableText(
                          root,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorsOf(context).textSecondary,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      history.isEmpty
                          ? tr(
                              '完成一次上传或下载后显示实际连接方式。',
                              'The connection is shown after a completed upload or download.',
                            )
                          : history.first.route == 'p2p'
                          ? tr(
                              '最近一次传输使用 P2P 加密直连。',
                              'The last transfer used an encrypted P2P connection.',
                            )
                          : tr(
                              '最近一次传输：${label(history.first.route)}。',
                              'Last transfer: ${label(history.first.route)}.',
                            ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final event in history)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                event.route == 'p2p' ? Icons.bolt : Icons.link,
                              ),
                              title: Text(
                                '${event.upload ? tr('上传', 'Upload') : tr('下载', 'Download')} · ${event.scope.path.replaceAll('\\', '/').split('/').last}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${label(event.route)} · ${'${event.time.toLocal()}'.split('.').first}',
                                  ),
                                  SelectableText(
                                    event.scope.path.startsWith('/') ||
                                            root.isEmpty
                                        ? event.scope.path
                                        : '${root.replaceFirst(RegExp(r'[\\/]$'), '')}/${event.scope.path}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 系统返回（左滑/返回键）：非根路径先逐级向上，到根才真正 pop（任务 B）。
    return PopScope(
      canPop: _path.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _open(filesParentPath(_path));
      },
      child: Theme(
        data: cortermToolTheme(context),
        child: Builder(
          builder: (context) {
            final c = colorsOf(context);
            return AdaptivePageScaffold(
              backgroundColor: c.background,
              appBar: AppBar(
                title: Text(
                  widget.workspaceName.isEmpty ? '电脑' : widget.workspaceName,
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.restore_from_trash_outlined),
                    tooltip: _tr('最近删除', 'Recently deleted'),
                    onPressed: _busy ? null : _showTrash,
                  ),
                  IconButton(
                    icon: const Icon(Icons.link),
                    tooltip: '连接方式',
                    onPressed: () => _showTransferConnection(context),
                  ),
                  PopupMenuButton<String>(
                    enabled: !_busy && !_picking,
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
                  _Breadcrumb(
                    path: _path,
                    rootLabel: widget.rootPath,
                    onNavigate: _open,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: TextField(
                      onChanged: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 20),
                        hintText:
                            Localizations.localeOf(context).languageCode == 'zh'
                            ? '搜索当前文件夹'
                            : 'Search this folder',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  Divider(color: c.divider, height: 1),
                  Expanded(
                    child: FutureBuilder<FileListing>(
                      future: _future,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return ErrorState(
                            message: fileErrorMessage(context, snap.error),
                            onRetry: () => _open(_path),
                          );
                        }
                        if (!snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final entries =
                            snap.data!.entries
                                .where(
                                  (e) => e.name.toLowerCase().contains(_query),
                                )
                                .toList()
                              ..sort((a, b) {
                                if (a.isDirectory != b.isDirectory) {
                                  return a.isDirectory ? -1 : 1;
                                }
                                return a.name.compareTo(b.name);
                              });
                        if (entries.isEmpty) {
                          return EmptyState(
                            icon: Icons.folder_open,
                            message: _query.isNotEmpty
                                ? (Localizations.localeOf(context)
                                              .languageCode ==
                                          'zh'
                                      ? '没有匹配的文件'
                                      : 'No matching files')
                                : (Localizations.localeOf(context)
                                              .languageCode ==
                                          'zh'
                                      ? '此文件夹为空'
                                      : 'This folder is empty'),
                          );
                        }
                        return RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: entries.length,
                            itemBuilder: (context, i) =>
                                _EntryTile(entry: entries[i], screen: this),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_transferError != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _transferError!,
                        style: TextStyle(color: c.danger),
                      ),
                    ),
                  if (_transfer case final control?)
                    ListenableBuilder(
                      listenable: control,
                      builder: (context, _) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '$_transferName · ${control.switching ? _tr('切换到', 'Switching to') : ''} ${_routeLabel(control.route)}',
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: control.total > 0
                                  ? (control.transferred / control.total).clamp(
                                      0,
                                      1,
                                    )
                                  : null,
                            ),
                            if (control.total > 0)
                              Text(
                                '${control.transferred} / ${control.total} B',
                              ),
                            TextButton(
                              onPressed: control.cancelToken.isCancelled
                                  ? null
                                  : () {
                                      control.cancel();
                                      setState(() {});
                                    },
                              child: Text(
                                control.cancelToken.isCancelled
                                    ? _tr('正在取消…', 'Cancelling…')
                                    : _tr('取消传输', 'Cancel transfer'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_busy && _transfer == null && !_editing)
                    const LinearProgressIndicator(minHeight: 2),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 上一级目录（任务 B）：'' 的上一级仍是 ''（根）。
String filesParentPath(String path) {
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return '';
  return segments.sublist(0, segments.length - 1).join('/');
}

/// 恢复的记忆路径已失效（Gateway 错误码 path_not_found / path_invalid）。
bool isStalePathError(Object error) =>
    error is ApiException &&
    (error.errorCode == 'path_not_found' || error.errorCode == 'path_invalid');

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
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 16, color: c.textPrimary),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
      trailing: PopupMenuButton<String>(
        enabled: !screen._busy,
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
          const PopupMenuItem(value: 'delete', child: Text('移到回收站')),
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
                child: Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: c.textSecondary,
                ),
              ),
            InkWell(
              onTap: i == 0
                  ? () => onNavigate('')
                  : () {
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
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

String _fmtTime(DateTime? utc) {
  if (utc == null) return '';
  final local = utc.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class _FileMutationSheet extends StatefulWidget {
  const _FileMutationSheet({
    required this.title,
    required this.initialName,
    required this.withContent,
    required this.existingNames,
    required this.submit,
  });
  final String title;
  final String initialName;
  final bool withContent;
  final Set<String> existingNames;
  final Future<void> Function(String, String) submit;
  @override
  State<_FileMutationSheet> createState() => _FileMutationSheetState();
}

class _FileMutationSheetState extends State<_FileMutationSheet> {
  late final _name = TextEditingController(text: widget.initialName);
  final _content = TextEditingController();
  bool _busy = false;
  bool _replace = false;
  String? _error;
  String? _details;
  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final name = _name.text.trim();
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\')) {
      setState(
        () => _error = zh
            ? '请输入不含路径分隔符的文件名。'
            : 'Enter a filename without path separators.',
      );
      return;
    }
    if (widget.withContent &&
        widget.existingNames.contains(name) &&
        !_replace) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.submit(name, _content.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = fileErrorMessage(context, error);
          _details = '$error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final overwrite =
        widget.withContent && widget.existingNames.contains(_name.text.trim());
    return PopScope(
      canPop: !_busy,
      child: Theme(
        data: cortermToolTheme(context),
        child: Builder(
          builder: (context) => Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              16,
              24,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  autofocus: true,
                  enabled: !_busy,
                  onChanged: (_) => setState(() {
                    _replace = false;
                    _error = null;
                  }),
                  decoration: InputDecoration(labelText: zh ? '名称' : 'Name'),
                ),
                if (widget.withContent) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _content,
                    enabled: !_busy,
                    minLines: 3,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: zh ? '内容（可为空）' : 'Contents (optional)',
                    ),
                  ),
                ],
                if (overwrite)
                  CheckboxListTile(
                    value: _replace,
                    title: Text(
                      zh ? '覆盖现有文件（原内容无法恢复）' : 'Replace existing file (original contents cannot be recovered)',
                    ),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _replace = value == true),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(color: colorsOf(context).danger),
                    ),
                  ),
                if (_details != null)
                  ExpansionTile(
                    title: Text(zh ? '详细信息' : 'Details'),
                    children: [SelectableText(_details!)],
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || (overwrite && !_replace) ? null : _save,
                  child: Text(
                    _busy ? (zh ? '保存中…' : 'Saving…') : (zh ? '保存' : 'Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrashRecoverySheet extends StatefulWidget {
  const _TrashRecoverySheet({required this.records, required this.restore});
  final List<Map<String, dynamic>> records;
  final Future<void> Function(Map<String, dynamic>) restore;
  @override
  State<_TrashRecoverySheet> createState() => _TrashRecoverySheetState();
}

class _TrashRecoverySheetState extends State<_TrashRecoverySheet> {
  String? _busyId;
  String? _error;
  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _busyId == null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _zh ? '最近删除' : 'Recently deleted',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          _zh
              ? '仅显示本机、当前账号的删除记录。文件保存在原电脑；恢复不会覆盖已有文件。待确认表示操作响应丢失或未成功，可尝试恢复以确认。'
              : 'Records belong to this account and device. Files stay on the original computer. Restore never overwrites existing files. Pending means the response was lost or the move failed; try restoring to confirm.',
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (widget.records.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(_zh ? '暂无删除记录' : 'No deleted items'),
          ),
        for (final record in widget.records.toList())
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(record['path'] as String),
            subtitle: record['pending'] == true
                ? Text(_zh ? '待确认' : 'Pending confirmation')
                : null,
            trailing: TextButton(
              onPressed: _busyId != null
                  ? null
                  : () async {
                      setState(() {
                        _busyId = record['id'] as String;
                        _error = null;
                      });
                      try {
                        await widget.restore(record);
                        if (mounted) {
                          setState(() => widget.records.remove(record));
                        }
                      } catch (e) {
                        if (mounted) {
                          setState(() => _error = fileErrorMessage(context, e));
                        }
                      } finally {
                        if (mounted) setState(() => _busyId = null);
                      }
                    },
              child: Text(
                _busyId == record['id']
                    ? (_zh ? '恢复中…' : 'Restoring…')
                    : (_zh ? '恢复' : 'Restore'),
              ),
            ),
          ),
      ],
    ),
  );
}
