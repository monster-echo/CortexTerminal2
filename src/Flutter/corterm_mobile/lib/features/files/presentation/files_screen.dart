import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/session.dart';
import '../../../core/models/workspace.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/states.dart';
import '../../sessions/data/sessions_providers.dart';
import '../../session/session_controller.dart';
import '../data/file_repository.dart';
import 'remote_dir_browser.dart';
import '../../workers/data/workspace_repository.dart';

/// 远程文件浏览 v2（对齐 ArkTS FileBrowserPage / FilesService）：
/// IA 约定（app-ia-design.md）——会话绑定工作区 → 以工作区为根（workspace 通道）；
/// 未绑定（ungrouped）→ 以终端 OSC 7 当前目录为根（worker 通道）。
/// 入口：终端 ⋯ 菜单 → 文件管理。
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

  /// cwd 模式（ungrouped 会话）：浏览根 = 终端 OSC 7 当前目录。
  String? _cwdRoot;
  String? _workerId;
  bool _workspaceLoading = true;
  String? _workspaceError;
  late String _path = widget.initialPath;
  late Future<FileListing> _future = _load(_path);

  bool _busy = false;
  double? _progress; // 0..1，null = 不确定进度

  Future<FileListing> _load(String path) {
    final ws = _workspace;
    if (ws != null) {
      return ref
          .read(fileRepositoryProvider)
          .list(workspaceId: ws.workspaceId, path: path);
    }
    return ref
        .read(fileRepositoryProvider)
        .listForWorker(workerId: _workerId!, root: _cwdRoot!, path: path);
  }

  /// 解析浏览作用域（IA 约定）：
  /// 会话绑定工作区 → 工作区模式；未绑定 → cwd 模式（根 = 终端当前目录）。
  Future<void> _resolveScope() async {
    try {
      final summaries =
          ref.read(sessionsProvider).value ?? const <SessionSummary>[];
      final session = summaries
          .where((s) => s.sessionId == widget.sessionId)
          .firstOrNull;
      final workerId = session?.workerId ?? widget.sessionId;
      _workerId = workerId;
      final workspaceId = session?.workspaceId ?? '';
      if (workspaceId.isNotEmpty) {
        final list = await ref.read(workspaceRepositoryProvider).list();
        final bound =
            list.where((w) => w.workspaceId == workspaceId).firstOrNull;
        if (!mounted) return;
        if (bound != null) {
          setState(() {
            _workspace = bound;
            _workspaceLoading = false;
            _path = '';
            _future = _load(_path);
          });
          return;
        }
      }
      // ungrouped：以终端当前目录为根。
      final cwd = ref
          .read(sessionControllerProvider)
          .entryOf(widget.sessionId)
          ?.remoteCwd;
      if (!mounted) return;
      setState(() {
        _cwdRoot = (cwd != null && cwd.isNotEmpty) ? cwd : null;
        _workspaceLoading = false;
        if (_cwdRoot != null) {
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


  Future<void> _download(FileEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final ws = _workspace;
    final root = ws?.rootPath ?? _cwdRoot;
    if (ws == null && root == null) return;
    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      final bytes = ws != null
          ? await ref.read(fileRepositoryProvider).downloadBytes(
                workspaceId: ws.workspaceId,
                path: _join(_path, entry.name),
              )
          : await ref.read(fileRepositoryProvider).downloadBytesForWorker(
                workerId: _workerId!,
                root: root!,
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
    final ws = _workspace;
    final root = ws?.rootPath ?? _cwdRoot;
    if (ws == null && root == null) return;
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
      if (ws != null) {
        await ref.read(fileRepositoryProvider).upload(
              workspaceId: ws.workspaceId,
              dirPath: _path,
              filename: picked.name,
              bytes: picked.bytes!,
            );
      } else {
        await ref.read(fileRepositoryProvider).uploadForWorker(
              workerId: _workerId!,
              root: root!,
              dirPath: _path,
              filename: picked.name,
              bytes: picked.bytes!,
            );
      }
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
    _resolveScope();
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
          _resolveScope();
        },
      );
    } else if (_workspace == null && _cwdRoot == null) {
      // ungrouped 且终端还没上报过 cwd：如实告知，不猜根目录。
      body = EmptyState(
        title: l10n.filesTitle,
        hint: l10n.filesCwdMissing,
      );
    } else {
      // OSC 7 联动：终端上报的当前目录若在工作区根内 → 提供一键跳转。
      final cwd = ref
          .watch(sessionControllerProvider)
          .entryOf(widget.sessionId)
          ?.remoteCwd;
      final ws = _workspace;
      // cwd 跳转条仅工作区模式：cwd 在工作区根内 → 一键跳转；根外 → 仅提示。
      String? cwdJump;
      if (ws != null && cwd != null && cwd.isNotEmpty) {
        final root = ws.rootPath ?? '/';
        final rootNorm = root.endsWith('/') && root.length > 1
            ? root.substring(0, root.length - 1)
            : root;
        cwdJump = (cwd == rootNorm || cwd.startsWith('$rootNorm/'))
            ? (cwd == rootNorm ? '' : cwd.substring(rootNorm.length + 1))
            : null;
      }

      body = Column(
        children: [
          if (ws != null && cwd != null && cwd.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: cwdJump == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        _open(cwdJump!);
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
            child: RemoteDirBrowser(
              future: _future,
              onRefresh: _refresh,
              path: _path,
              onNavigate: _open,
              fileTrailing: (e) => _busy
                  ? const SizedBox.shrink()
                  : ShadIconButton.ghost(
                      icon: const Icon(LucideIcons.download, size: 20),
                      onPressed: () => _download(e),
                    ),
              onFileTap: (e) {
                final ws = _workspace;
                if (ws != null) {
                  context.push(
                    '/files/${widget.sessionId}/preview'
                    '?workspaceId=${Uri.encodeComponent(ws.workspaceId)}'
                    '&path=${Uri.encodeComponent(_join(_path, e.name))}'
                    '&name=${Uri.encodeComponent(e.name)}'
                    '&size=${e.sizeBytes}',
                  );
                } else {
                  // cwd 模式：点文件直接下载分享（预览页仅工作区模式支持）。
                  _download(e);
                }
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
        bottom: (_workspace == null && _cwdRoot == null)
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
      floatingActionButton: (_workspace == null && _cwdRoot == null)
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

