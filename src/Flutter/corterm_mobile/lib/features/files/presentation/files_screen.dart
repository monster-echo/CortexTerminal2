import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/session.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/list_group.dart';
import '../../../shared/widgets/sheets_and_dialogs.dart';
import '../../../shared/widgets/states.dart';
import '../../sessions/data/sessions_providers.dart';
import '../../workspace/workspace_controller.dart';
import '../data/file_repository.dart';

/// 远程文件浏览 v2（对齐 ArkTS FileBrowserPage / FilesService）：
/// 以【工作区】为边界（绑定 Worker + 根路径），'' = 工作区根。
/// 打开时自动解析该 Worker 的第一个工作区；没有则引导创建。
/// 入口：终端 ⋯ 菜单 → 文件管理（sessionId 参数实为 Worker 绑定键）。
class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key, required this.sessionId, this.initialPath = ''});

  /// 终端菜单带入的会话 ID；文件操作按其所属 Worker 的工作区解析。
  final String sessionId;
  final String initialPath;

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  Workspace? _workspace;
  bool _workspaceLoading = true;
  String? _workspaceError;
  late String _path = widget.initialPath;
  late Future<FileListing> _future = _load(_path);

  bool _busy = false;
  double? _progress; // 0..1，null = 不确定进度

  Future<FileListing> _load(String path) {
    return ref
        .read(fileRepositoryProvider)
        .list(workspaceId: _workspace!.workspaceId, path: path);
  }

  /// 解析该 Worker 的工作区：有 → 直接进入；无 → 空态引导创建。
  Future<void> _resolveWorkspace() async {
    try {
      final summaries =
          ref.read(sessionsProvider).value ?? const <SessionSummary>[];
      final workerId = summaries
              .where((s) => s.sessionId == widget.sessionId)
              .firstOrNull
              ?.workerId ??
          widget.sessionId;
      final list = await ref.read(fileRepositoryProvider).listWorkspaces();
      final mine = list.where((w) => w.workerId == workerId).toList();
      if (!mounted) return;
      setState(() {
        _workspace = mine.isEmpty ? null : mine.first;
        _workspaceLoading = false;
        if (_workspace != null) {
          _path = '';
          _future = _load(_path);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _workspaceError = '$e';
        _workspaceLoading = false;
      });
    }
  }

  Future<void> _createWorkspace() async {
    final l10n = AppLocalizations.of(context)!;
    final nameController = TextEditingController();
    final rootController = TextEditingController(text: '/');
    final ok = await showCortermSheetDialog<bool>(
      context: context,
      title: l10n.workspaceCreateTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShadInputFormField(
            controller: nameController,
            label: Text(l10n.workspaceNameLabel),
            placeholder: Text(l10n.workspaceNameHint),
          ),
          const SizedBox(height: 12),
          ShadInputFormField(
            controller: rootController,
            label: Text(l10n.workspaceRootLabel),
            placeholder: Text(l10n.workspaceRootHint),
          ),
        ],
      ),
      actions: [
        ShadButton.ghost(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        ShadButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.create),
        ),
      ],
    );
    if (ok != true) return;
    final name = nameController.text.trim();
    final root = rootController.text.trim();
    if (name.isEmpty || root.isEmpty) return;
    try {
      final ws = await ref.read(fileRepositoryProvider).createWorkspace(
            workerId: widget.sessionId,
            name: name,
            rootPath: root,
          );
      if (!mounted) return;
      setState(() {
        _workspace = ws;
        _path = '';
        _future = _load(_path);
      });
    } catch (e) {
      if (mounted) showAppToast(context, '$e', destructive: true);
    }
  }

  void _open(String path) {
    setState(() {
      _path = path;
      _future = _load(path);
    });
  }

  Future<void> _refresh() async {
    setState(() => _future = _load(_path));
    await _future;
  }

  String _join(String dir, String name) =>
      dir.isEmpty ? name : '$dir/$name';

  String? _parentOf(String path) {
    if (path.isEmpty) return null;
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return '';
    return path.substring(0, idx);
  }

  Future<void> _download(FileEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      final bytes = await ref.read(fileRepositoryProvider).downloadBytes(
            workspaceId: _workspace!.workspaceId,
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
      if (!mounted) return;
      showAppToast(context, '${l10n.downloadFailed}: $e', destructive: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _upload() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await FilePicker.pickFiles(
      withData: true,
      type: FileType.any,
    );
    final picked = result?.files.firstOrNull;
    if (picked == null || picked.bytes == null) return;
    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      await ref.read(fileRepositoryProvider).upload(
            workspaceId: _workspace!.workspaceId,
            dirPath: _path,
            filename: picked.name,
            bytes: picked.bytes!,
          );
      if (!mounted) return;
      showAppToast(context, l10n.uploadDone);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '${l10n.uploadFailed}: $e', destructive: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _resolveWorkspace();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = ShadTheme.of(context).colorScheme;

    Widget body;
    if (_workspaceLoading) {
      body = const Center(child: ShadProgress(value: null));
    } else if (_workspaceError != null) {
      body = ErrorState(
        message: _workspaceError!,
        onRetry: () {
          setState(() {
            _workspaceLoading = true;
            _workspaceError = null;
          });
          _resolveWorkspace();
        },
      );
    } else if (_workspace == null) {
      body = EmptyState(
        title: l10n.workspaceNoneTitle,
        hint: l10n.workspaceNoneHint,
        actionLabel: l10n.create,
        onAction: _createWorkspace,
      );
    } else {
      // OSC 7 联动：终端上报的当前目录若在工作区根内 → 提供一键跳转。
      final cwd = ref
          .watch(workspaceControllerProvider)
          .entryOf(widget.sessionId)
          ?.remoteCwd;
      final root = _workspace!.rootPath ?? '/';
      final rootNorm = root.endsWith('/') && root.length > 1
          ? root.substring(0, root.length - 1)
          : root;
      final cwdJump = (cwd == null || cwd.isEmpty)
          ? null
          : (cwd == rootNorm || cwd.startsWith('$rootNorm/'))
              ? (cwd == rootNorm
                  ? ''
                  : cwd.substring(rootNorm.length + 1))
              : null;

      body = Column(
        children: [
          if (cwd != null && cwd.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: cwdJump == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        _open(cwdJump);
                      },
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.border),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.terminal,
                          size: 14, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          cwd,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShadTheme.of(context)
                              .textTheme
                              .muted
                              .copyWith(color: scheme.mutedForeground),
                        ),
                      ),
                      Text(
                        cwdJump == null ? l10n.workspaceCwdOutside : l10n.jump,
                        style: ShadTheme.of(context).textTheme.muted.copyWith(
                              color: cwdJump == null
                                  ? scheme.mutedForeground
                                  : scheme.primary,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (_busy && _progress != null)
            LinearProgressIndicator(value: _progress),
          Expanded(
            child: FutureBuilder<FileListing>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return ErrorState(
                    message: '${snap.error}',
                    onRetry: _refresh,
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: ShadProgress(value: null));
                }
                final listing = snap.data!;
                final parent = _parentOf(_path);
                final entries = listing.entries;
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    children: [
                      if (parent != null)
                        AppRow(
                          icon: LucideIcons.arrowUp,
                          label: '..',
                          onTap: () => _open(parent),
                        ),
                      for (final e in entries)
                        AppRow(
                          icon: e.isDirectory
                              ? LucideIcons.folder
                              : LucideIcons.file,
                          label: e.name,
                          value:
                              e.isDirectory ? null : _fmtSize(e.sizeBytes),
                          trailing: e.isDirectory
                              ? null
                              : (_busy
                                  ? null
                                  : ShadIconButton.ghost(
                                      icon: const Icon(LucideIcons.download,
                                          size: 20),
                                      onPressed: () => _download(e),
                                    )),
                          chevron: e.isDirectory,
                          onTap: e.isDirectory
                              ? () => _open(_join(_path, e.name))
                              : () => context.push(
                                    '/files/${widget.sessionId}/preview'
                                    '?workspaceId=${Uri.encodeComponent(_workspace!.workspaceId)}'
                                    '&path=${Uri.encodeComponent(_join(_path, e.name))}'
                                    '&name=${Uri.encodeComponent(e.name)}'
                                    '&size=${e.sizeBytes}',
                                  ),
                        ),
                      if (entries.isEmpty && parent != null)
                        SizedBox(
                          height: 160,
                          child: Center(
                            child: Text(
                              l10n.emptyFolder,
                              style:
                                  TextStyle(color: scheme.mutedForeground),
                            ),
                          ),
                        ),
                      if (listing.truncated)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            l10n.listTruncated,
                            style: TextStyle(color: scheme.mutedForeground),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: CortermAppBar(
        leading: ShadIconButton.ghost(
          foregroundColor: scheme.foreground,
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => context.pop(),
        ),
        title: l10n.filesTitle,
        bottom: _workspace == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(30),
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding:
                        const EdgeInsets.only(left: 16, right: 16, bottom: 6),
                    child: _PathBreadcrumb(path: _path, onNavigate: _open),
                  ),
                ),
              ),
      ),
      floatingActionButton: _workspace == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _upload,
              backgroundColor: scheme.primary,
              foregroundColor: scheme.primaryForeground,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: ShadProgress(value: null))
                  : const Icon(LucideIcons.fileUp),
              label: Text(l10n.upload),
            ),
      body: body,
    );
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// 路径面包屑（官方 ShadBreadcrumb）：根目录 + 逐级段，父级可点回跳；
/// 当前段高亮（lastItemTextColor 默认 foreground），超宽横向滚动不换行。
class _PathBreadcrumb extends StatelessWidget {
  const _PathBreadcrumb({required this.path, required this.onNavigate});

  final String path;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final items = <Widget>[
      ShadBreadcrumbLink(
        onPressed: () => onNavigate(''),
        child: Icon(LucideIcons.home,
            size: 13, color: ShadTheme.of(context).colorScheme.mutedForeground),
      ),
    ];
    var accumulated = '';
    for (final (i, segment) in segments.indexed) {
      accumulated = accumulated.isEmpty ? '/$segment' : '$accumulated/$segment';
      final target = accumulated;
      if (i == segments.length - 1) {
        items.add(Text(segment));
      } else {
        items.add(
          ShadBreadcrumbLink(
            onPressed: () => onNavigate(target),
            child: Text(segment),
          ),
        );
      }
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ShadBreadcrumb(children: items, spacing: 4),
    );
  }
}

